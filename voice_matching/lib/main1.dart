import 'dart:io'; // Untuk Directory dan File
import 'dart:math'; // Untuk sqrt
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Voice Matching App',
      home: VoiceComparisonScreen(),
    );
  }
}

class VoiceComparisonScreen extends StatefulWidget {
  const VoiceComparisonScreen({Key? key}) : super(key: key);

  @override
  _VoiceComparisonScreenState createState() => _VoiceComparisonScreenState();
}

class _VoiceComparisonScreenState extends State<VoiceComparisonScreen> {
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _firstFilePath;
  String? _secondFilePath;

  @override
  void initState() {
    super.initState();
    requestMicrophonePermission();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
  }

  Future<void> requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
    super.dispose();
  }

  Future<String> _getTempFilePath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/voice_record_${DateTime.now().millisecondsSinceEpoch}.aac';
  }

  Future<void> _startRecording(bool isFirst) async {
    if (_isRecording) return;

    final filePath = await _getTempFilePath();
    await _recorder!.startRecorder(toFile: filePath);

    setState(() {
      _isRecording = true;
      if (isFirst) {
        _firstFilePath = filePath;
      } else {
        _secondFilePath = filePath;
      }
    });
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    await _recorder!.stopRecorder();
    setState(() {
      _isRecording = false;
    });
  }

  // Menghitung Cosine Similarity antara dua vektor
  double cosineSimilarity(List<int> vectorA, List<int> vectorB) {
  int minLength = min(vectorA.length, vectorB.length);  // Dapatkan panjang terpendek dari dua vektor

  double dotProduct = 0;
  double magnitudeA = 0;
  double magnitudeB = 0;

  // Lakukan perhitungan hanya hingga panjang terpendek
  for (int i = 0; i < minLength; i++) {
    dotProduct += vectorA[i] * vectorB[i];
    magnitudeA += vectorA[i] * vectorA[i];
    magnitudeB += vectorB[i] * vectorB[i];
  }

  magnitudeA = sqrt(magnitudeA);
  magnitudeB = sqrt(magnitudeB);

  if (magnitudeA == 0 || magnitudeB == 0) {
    return 0.0;  // Hindari pembagian dengan nol
  }

  return dotProduct / (magnitudeA * magnitudeB);
}


  Future<List<int>> _getAudioBytes(String filePath) async {
    final audioFile = File(filePath);
    final audioData = await audioFile.readAsBytes();
    return audioData;
  }

  Future<void> _compareVoices() async {
    if (_firstFilePath == null || _secondFilePath == null) return;

    final audioBytes1 = await _getAudioBytes(_firstFilePath!);
    final audioBytes2 = await _getAudioBytes(_secondFilePath!);

    // Menghitung Cosine Similarity antara dua file audio
    final similarity = cosineSimilarity(audioBytes1, audioBytes2);

    final result = similarity >= 0.7 ? 'Suara mirip' : 'Suara tidak mirip';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Hasil Perbandingan"),
          content: Text('Hasil: $result\nCosine Similarity: ${similarity.toStringAsFixed(2)}'),
          actions: [
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Comparison')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Rekam suara pertama dan kedua, lalu bandingkan"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isRecording ? null : () => _startRecording(true),
              child: const Text("Mulai Rekam (Suara 1)"),
            ),
            ElevatedButton(
              onPressed: !_isRecording ? null : () => _stopRecording(),
              child: const Text("Berhenti Rekam (Suara 1)"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isRecording ? null : () => _startRecording(false),
              child: const Text("Mulai Rekam (Suara 2)"),
            ),
            ElevatedButton(
              onPressed: !_isRecording ? null : () => _stopRecording(),
              child: const Text("Berhenti Rekam (Suara 2)"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _compareVoices,
              child: const Text("Bandingkan Suara"),
            ),
          ],
        ),
      ),
    );
  }
}
