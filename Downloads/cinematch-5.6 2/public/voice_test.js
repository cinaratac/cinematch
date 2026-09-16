const startButton = document.getElementById('startButton');
const stopButton = document.getElementById('stopButton');
const statusDiv = document.getElementById('status');

let socket;
let localStream;
let inputContext;
let outputContext;
let workletNode;
let silentGain;
let nextPlaybackTime = 0;
let scheduledSources = new Set();
let keepaliveTimer;
let userTranscript = '';
let assistantTranscript = '';
let agentSpeaking = false;
let serverAudioDonePending = false;

const commaSeparatedValues = (elementId) => (
    document.getElementById(elementId).value
        .split(',')
        .map(value => value.trim())
        .filter(Boolean)
);

function getVoiceApiSettings() {
    const baseUrl = document.getElementById('apiBaseUrl').value
        .trim()
        .replace(/\/+$/, '');
    const apiKey = document.getElementById('voiceApiKey').value.trim();
    if (!baseUrl) throw new Error('Voice API adresini girin.');
    if (!apiKey) throw new Error('Voice API anahtarını girin.');
    return { baseUrl, apiKey };
}

function updateTranscriptStatus(fallback) {
    if (userTranscript || assistantTranscript) {
        statusDiv.innerText =
            `Sen: ${userTranscript || '...'} — CineMatch: ${assistantTranscript || '...'}`;
    } else {
        statusDiv.innerText = fallback;
    }
}

function interruptPlayback() {
    serverAudioDonePending = false;
    for (const source of scheduledSources) {
        try {
            source.stop();
        } catch (_) {
            // Kaynak daha önce sona ermiş olabilir.
        }
    }
    scheduledSources.clear();
    if (outputContext) nextPlaybackTime = outputContext.currentTime;
}

function reportPlaybackDoneIfReady() {
    if (
        !serverAudioDonePending
        || scheduledSources.size
        || socket?.readyState !== WebSocket.OPEN
    ) {
        return;
    }
    serverAudioDonePending = false;
    socket.send(JSON.stringify({ type: 'playback_done' }));
    agentSpeaking = false;
    updateTranscriptStatus('Durum: Seni dinliyorum...');
}

function playPcmChunk(arrayBuffer) {
    if (!outputContext || arrayBuffer.byteLength < 2) return;
    const usableLength = arrayBuffer.byteLength - (arrayBuffer.byteLength % 2);
    const view = new DataView(arrayBuffer, 0, usableLength);
    const frameCount = usableLength / 2;
    const audioBuffer = outputContext.createBuffer(1, frameCount, 24000);
    const channel = audioBuffer.getChannelData(0);
    for (let index = 0; index < frameCount; index += 1) {
        channel[index] = view.getInt16(index * 2, true) / 32768;
    }

    const source = outputContext.createBufferSource();
    source.buffer = audioBuffer;
    source.connect(outputContext.destination);
    const startAt = Math.max(
        nextPlaybackTime,
        outputContext.currentTime + (scheduledSources.size ? 0 : 0.04),
    );
    source.start(startAt);
    nextPlaybackTime = startAt + audioBuffer.duration;
    scheduledSources.add(source);
    source.onended = () => {
        scheduledSources.delete(source);
        reportPlaybackDoneIfReady();
    };
}

async function prepareAudio() {
    localStream = await navigator.mediaDevices.getUserMedia({
        audio: {
            channelCount: 1,
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
        },
    });
    inputContext = new AudioContext();
    outputContext = new AudioContext({ sampleRate: 24000 });
    await Promise.all([inputContext.resume(), outputContext.resume()]);
    await inputContext.audioWorklet.addModule(
        `/voice_pcm_processor.js?v=streaming-20260727-2`,
    );

    const microphone = inputContext.createMediaStreamSource(localStream);
    workletNode = new AudioWorkletNode(inputContext, 'voice-pcm-processor');
    silentGain = inputContext.createGain();
    silentGain.gain.value = 0;
    microphone.connect(workletNode);
    workletNode.connect(silentGain);
    silentGain.connect(inputContext.destination);

    workletNode.port.onmessage = (event) => {
        if (event.data instanceof ArrayBuffer && socket?.readyState === WebSocket.OPEN) {
            socket.send(event.data);
        }
    };
}

function stopVoice(message = 'Durum: Bağlantı kapatıldı.') {
    clearInterval(keepaliveTimer);
    keepaliveTimer = null;
    interruptPlayback();
    if (workletNode) workletNode.disconnect();
    if (silentGain) silentGain.disconnect();
    workletNode = null;
    silentGain = null;
    if (localStream) localStream.getTracks().forEach(track => track.stop());
    localStream = null;
    if (inputContext) inputContext.close().catch(() => {});
    if (outputContext) outputContext.close().catch(() => {});
    inputContext = null;
    outputContext = null;
    const activeSocket = socket;
    socket = null;
    if (activeSocket) activeSocket.close();
    nextPlaybackTime = 0;
    userTranscript = '';
    assistantTranscript = '';
    agentSpeaking = false;
    statusDiv.innerText = message;
    startButton.disabled = false;
    stopButton.disabled = true;
}

async function startVoice() {
    stopVoice('Durum: Yeni bağlantı hazırlanıyor...');
    startButton.disabled = true;
    stopButton.disabled = false;

    try {
        const { baseUrl, apiKey } = getVoiceApiSettings();
        statusDiv.innerText = 'Durum: Mikrofona erişiliyor...';
        await prepareAudio();

        const wsUrl = baseUrl.replace(/^http/, 'ws') + '/api/voice/stream';
        socket = new WebSocket(wsUrl);
        socket.binaryType = 'arraybuffer';

        socket.addEventListener('open', () => {
            socket.send(JSON.stringify({
                type: 'auth',
                api_key: apiKey,
                sample_rate: inputContext.sampleRate,
                user_id: document.getElementById('userId').value.trim()
                    || 'voice-test-user',
                username: document.getElementById('username').value.trim()
                    || 'Voice Test',
                favorite_genres: commaSeparatedValues('favoriteGenres'),
                favorite_directors: [],
                favorite_actors: [],
                favorite_movies: [],
            }));
            keepaliveTimer = setInterval(() => {
                if (socket?.readyState === WebSocket.OPEN) {
                    socket.send(JSON.stringify({ type: 'keepalive' }));
                }
            }, 8000);
        });

        socket.addEventListener('message', (event) => {
            if (event.data instanceof ArrayBuffer) {
                playPcmChunk(event.data);
                return;
            }

            const message = JSON.parse(event.data);
            if (message.type === 'connecting') {
                statusDiv.innerText = 'Durum: Deepgram bağlantısı kuruluyor...';
            } else if (message.type === 'ready') {
                statusDiv.innerText = 'Durum: Bağlandı! Şimdi konuşabilirsiniz.';
            } else if (message.type === 'transcript') {
                if (message.role === 'user') {
                    userTranscript = message.content;
                    assistantTranscript = '';
                } else if (message.role === 'assistant') {
                    assistantTranscript = message.content;
                }
                updateTranscriptStatus('Durum: Konuşma sürüyor...');
            } else if (message.type === 'processing') {
                updateTranscriptStatus('Durum: CineMatch düşünüyor...');
            } else if (message.type === 'speaking') {
                agentSpeaking = true;
                updateTranscriptStatus('Durum: CineMatch konuşuyor...');
            } else if (message.type === 'interrupt') {
                agentSpeaking = false;
                interruptPlayback();
                statusDiv.innerText = 'Durum: Seni dinliyorum...';
            } else if (message.type === 'audio_done') {
                serverAudioDonePending = true;
                reportPlaybackDoneIfReady();
            } else if (message.type === 'warning') {
                console.warn('Deepgram uyarısı:', message.message);
            } else if (message.type === 'error') {
                statusDiv.innerText = `Hata: ${message.message}`;
            }
        });

        socket.addEventListener('close', (event) => {
            if (!socket) return;
            stopVoice(
                event.code === 4001
                    ? 'Hata: Voice API anahtarı geçersiz.'
                    : 'Durum: Sunucu bağlantısı kapandı.',
            );
        });
        socket.addEventListener('error', () => {
            stopVoice('Hata: Voice WebSocket bağlantısı kurulamadı.');
        });
    } catch (error) {
        console.error('Hata:', error);
        stopVoice(`Hata: ${error.message}`);
    }
}

startButton.addEventListener('click', startVoice);
stopButton.addEventListener('click', () => stopVoice());
window.addEventListener('beforeunload', () => stopVoice());
