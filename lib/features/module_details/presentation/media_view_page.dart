import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../data/repositories/api_repository.dart';
import '../../../core/constants/app_colors.dart';

class MediaViewPage extends ConsumerStatefulWidget {
  final String type;
  const MediaViewPage({super.key, required this.type});

  @override
  ConsumerState<MediaViewPage> createState() => _MediaViewPageState();
}

class _MediaViewPageState extends ConsumerState<MediaViewPage> {
  YoutubePlayerController? _ytController;

  void _initYoutube(String url) {
    String? videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId != null && _ytController == null) {
      _ytController = YoutubePlayerController(
        initialVideoId: videoId,
        flags: const YoutubePlayerFlags(
          autoPlay: false,
          mute: false,
          disableDragSeek: false,
          loop: false,
          isLive: false,
          forceHD: false,
          enableCaption: true,
          // XAVFSIZLIK: YouTube logotipi va shareni cheklash
          hideControls: false,
          controlsVisibleAtStart: true,
        ),
      );
    }
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Faylni ochib bo\'lmadi')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ytController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(moduleDataProvider);
    if (data == null) return const Center(child: Text('Ma\'lumot yo\'q'));

    final url = widget.type == 'pdf' ? data.pdfUrl : data.videoUrl;
    if (url.isEmpty) return const Center(child: Text('Fayl kiritilmagan'));

    if (widget.type == 'video') {
      _initYoutube(url);
      return Column(
        children: [
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(data.artikul, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          // Stack orqali YouTube Share va Logotipni bloklash (Pointer Interceptor mantiqi)
          Stack(
            children: [
              YoutubePlayer(
                controller: _ytController!,
                showVideoProgressIndicator: true,
                progressIndicatorColor: AppColors.accent,
              ),
              // Videoning tepa o'ng burchagidagi "Share" va "YouTube" logotipini bosishdan himoya
              Positioned(
                top: 0, right: 0, width: 80, height: 80,
                child: GestureDetector(onTap: () {}, child: Container(color: Colors.transparent)),
              ),
              Positioned(
                bottom: 0, right: 0, width: 80, height: 50,
                child: GestureDetector(onTap: () {}, child: Container(color: Colors.transparent)),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Video faqat Aristokrat Mebel xodimlari uchun.', 
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textGray)),
          ),
        ],
      );
    }

    // PDF ko'rinishi (URL Launcher bilan)
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.picture_as_pdf, size: 100, color: AppColors.danger),
          const SizedBox(height: 20),
          Text(data.nomi, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () => _launchURL(url),
            icon: const Icon(Icons.open_in_new),
            label: const Text('Chizmani ochish'),
          ),
        ],
      ),
    );
  }
}
