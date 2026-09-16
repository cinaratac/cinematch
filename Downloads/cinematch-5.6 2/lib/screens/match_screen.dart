import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

import 'package:fluttergirdi/services/match_service.dart' as global_match;
import 'package:fluttergirdi/services/global_data_service.dart';
import 'package:fluttergirdi/widgets/match_card.dart'; // YENİ DOSYAMIZI İÇERİ ALIYORUZ

class MatchListScreen extends StatefulWidget {
  const MatchListScreen({super.key});

  @override
  State<MatchListScreen> createState() => _MatchListScreenState();
}

class _MatchListScreenState extends State<MatchListScreen> {
  List<global_match.MatchResult> _all = [];
  bool _loading = true;
  final PageController _pageController = PageController();
  String? _lastMarkedSeenUid;
  StreamSubscription<List<global_match.MatchResult>>? _matchSubscription;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  @override
  void dispose() {
    _matchSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _loadMatches({bool forceRefresh = false}) {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;

    if (forceRefresh) {
      global_match.MatchService.instance.clearCache();
    }

    setState(() => _loading = true);

    if (!forceRefresh &&
        GlobalDataService.instance.myMatches != null &&
        GlobalDataService.instance.myMatches!.isNotEmpty) {
      if (mounted) {
        setState(() {
          _all = GlobalDataService.instance.myMatches!;
          _loading = false;
        });
      }
    }

    _matchSubscription?.cancel();
    _matchSubscription = global_match.MatchService.instance
        .findMatchesStream(me.uid)
        .listen(
          (results) {
            if (!mounted) return;
            setState(() {
              _all = results;
              _loading = false;
            });
            if (_all.isNotEmpty) {
              _markVisibleAsSeen(me.uid, _all.first.uid);
            }
          },
          onError: (e) {
            debugPrint("Match yükleme hatası: $e");
            if (!mounted) return;
            setState(() {
              _loading = false;
              if (_all.isEmpty) _all = [];
            });
          },
        );
  }

  void _markVisibleAsSeen(String myUid, String targetUid) {
    if (_lastMarkedSeenUid == targetUid) return;
    _lastMarkedSeenUid = targetUid;
    global_match.MatchService.instance.markAsSeen(myUid, targetUid);
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser;

    if (me == null) {
      return const Scaffold(
        body: Center(child: Text('Oturum açmanız gerekiyor')),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        
        centerTitle: true,
      ),
      body: _loading && _all.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.green))
          : _all.isEmpty
          ? const _NoMatchesCharacter()
          : PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              allowImplicitScrolling: false,
              onPageChanged: (index) {
                _markVisibleAsSeen(me.uid, _all[index].uid);
              },
              itemCount: _all.length,
              itemBuilder: (context, index) {
                final m = _all[index];
                // Dışarıdan çağırdığımız o temiz widget'ı basıyoruz
                return RepaintBoundary(
                  key: ValueKey(m.uid),
                  child: MatchCard(result: m),
                );
              },
            ),
    );
  }
}

class _NoMatchesCharacter extends StatelessWidget {
  const _NoMatchesCharacter();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.theater_comedy_rounded,
            size: 100,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 16),
          const Text(
            'Şimdilik bu kadar!',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Daha fazla ortak zevk için filmlerini puanla.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
