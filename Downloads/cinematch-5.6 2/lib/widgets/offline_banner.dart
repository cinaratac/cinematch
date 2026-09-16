import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  late final Stream<List<ConnectivityResult>> _connectivityStream;

  @override
  void initState() {
    super.initState();
    _connectivityStream = Connectivity().onConnectivityChanged;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: _connectivityStream,
      builder: (context, snapshot) {
        // İlk açılışta veri yoksa veya bağlantı varsa boş döndür
        final results = snapshot.data;

        // connectivity_plus v6+ liste döndürür.
        // Eğer liste 'none' içeriyorsa internet yok demektir.
        final isOffline =
            results != null && results.contains(ConnectivityResult.none);

        // Animasyonlu görünüm için AnimatedSwitcher kullanıyoruz
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return SizeTransition(sizeFactor: animation, child: child);
          },
          child: isOffline
              ? Container(
                  key: const ValueKey('offline_banner'),
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.error,
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'İnternet bağlantısı yok',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(), // İnternet varsa hiçbir şey çizme (0 boyut)
        );
      },
    );
  }
}
