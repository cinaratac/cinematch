class VoicePcmProcessor extends AudioWorkletProcessor {
    constructor() {
        super();
        this.samples = [];
        this.frameSize = Math.max(128, Math.round(sampleRate / 50));
        this.voiceFrames = 0;
        this.silentFrames = 0;
        this.voiceActive = false;
    }

    process(inputs) {
        const channel = inputs[0]?.[0];
        if (!channel) return true;

        for (let index = 0; index < channel.length; index += 1) {
            const value = Math.max(-1, Math.min(1, channel[index]));
            this.samples.push(value < 0 ? value * 32768 : value * 32767);
        }

        while (this.samples.length >= this.frameSize) {
            const pcm = new Int16Array(this.frameSize);
            for (let index = 0; index < this.frameSize; index += 1) {
                pcm[index] = this.samples[index];
            }
            this.samples.splice(0, this.frameSize);

            let energy = 0;
            for (let index = 0; index < pcm.length; index += 1) {
                const normalized = pcm[index] / 32768;
                energy += normalized * normalized;
            }
            const rms = Math.sqrt(energy / pcm.length);
            this.voiceFrames = rms > 0.032 ? this.voiceFrames + 1 : 0;
            this.silentFrames = rms < 0.018 ? this.silentFrames + 1 : 0;

            // Yaklaşık 60 ms doğrulama, klavye tıklaması gibi tek karelik
            // seslerin cevabı yanlışlıkla kesmesini engeller.
            if (!this.voiceActive && this.voiceFrames >= 3) {
                this.voiceActive = true;
                this.silentFrames = 0;
                this.port.postMessage({ type: 'voice_start', rms });
            } else if (this.voiceActive && this.silentFrames >= 15) {
                this.voiceActive = false;
                this.voiceFrames = 0;
                this.port.postMessage({ type: 'voice_end' });
            }
            this.port.postMessage(pcm.buffer, [pcm.buffer]);
        }
        return true;
    }
}

registerProcessor('voice-pcm-processor', VoicePcmProcessor);
