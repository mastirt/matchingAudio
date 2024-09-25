import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:fftea/fftea.dart';
import 'dart:math'; // Add this import
import 'dart:math' as math; // To avoid naming conflicts
import 'package:scidart/numdart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
  String? _sampleFilePath;
  List<double>? _sampleMFCC;
  String _comparisonResult = "Rekam sample suara, lalu mulai perbandingan real-time.";
  Timer? _timer; // Timer for real-time comparison
  double _similarity = 0.0;
  bool _isComparing = false; // Flag to check if real-time comparison is active

  @override
  void initState() {
    super.initState();
    requestMicrophonePermission();
    _recorder = FlutterSoundRecorder();
    _initializeRecorder();
  }

  Future<void> _initializeRecorder() async {
    await _recorder!.openRecorder();
  }

  Future<void> requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder?.closeRecorder();
    _recorder = null;
    super.dispose();
  }

  Future<String> _getSampleFilePath() async {
    final tempDir = await getTemporaryDirectory();
    return '${tempDir.path}/sample_suara.aac';
  }

  // Record sample voice for 1 second
  Future<void> _recordSample() async {
    final filePath = await _getSampleFilePath();

    // Ensure recorder is ready
    if (_recorder!.isRecording) {
      await _recorder!.stopRecorder();
    }

    await _recorder!.startRecorder(
      toFile: filePath,
      codec: Codec.aacADTS,
    );

    setState(() {
      _isRecording = true;
    });

    // Record for 1 second
    await Future.delayed(const Duration(seconds: 5));

    await _recorder!.stopRecorder();

    // Extract waveform and compute MFCC from sample voice
    String pcmPath = await _extractWaveform(filePath);
    final audioBytes = await _getAudioBytes(pcmPath);
    _sampleMFCC = computeMFCC(audioBytes, 16000, 13);

    setState(() {
      _isRecording = false;
      _sampleFilePath = filePath;
      _comparisonResult = "Sample suara berhasil direkam. Mulai perbandingan real-time.";
    });
  }

  Future<String> _extractWaveform(String inputPath) async {
    String outputPath = '${inputPath}_waveform.pcm';

    // Wrap paths in quotes to handle spaces
    String command = '-y -i "$inputPath" -ar 16000 -ac 1 -f s16le "$outputPath"';

    await FFmpegKit.execute(command).then((session) async {
      final returnCode = await session.getReturnCode();
      if (returnCode != null && returnCode.isValueSuccess()) {
        print('Waveform extracted successfully for $inputPath');
      } else {
        final output = await session.getOutput();
        print('Error extracting waveform: $output');
      }
    });

    return outputPath;
  }

  Future<List<int>> _getAudioBytes(String filePath) async {
    final audioFile = File(filePath);
    if (!await audioFile.exists()) {
      throw Exception("Audio file not found at path: $filePath");
    }
    final audioData = await audioFile.readAsBytes();
    print(audioData);
    return audioData;
  }

  List<double> normalizeAudioData(List<int> audioBytes) {
    List<double> normalizedData = [];
    for (int i = 0; i < audioBytes.length - 1; i += 2) {
      int sample = audioBytes[i] | (audioBytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      normalizedData.add(sample / 32768.0);
    }
    print(normalizedData);

    // Ensure not all values are zero
    if (normalizedData.every((sample) => sample == 0)) {
      throw Exception("Audio normalization failed. All samples are zero.");
    }

    return normalizedData;
  }

  List<double> computeMFCC(List<int> audioBytes, int sampleRate, int numCoefficients) {
    var audioSignal = normalizeAudioData(audioBytes);

    final chunkSize = 512;
    final stft = STFT(chunkSize, Window.hanning(chunkSize));
    final spectrogram = <Float64List>[];

    stft.run(audioSignal, (Float64x2List freq) {
      final magnitudes = freq.discardConjugates().magnitudes();
      spectrogram.add(magnitudes);
    });

    var mfccList = <double>[];
    for (var frame in spectrogram) {
      mfccList.addAll(frame.getRange(0, math.min(numCoefficients, frame.length)));
    }
    print(mfccList);

    return mfccList;
  }

  double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
    int minLength = math.min(vectorA.length, vectorB.length);
    double dotProduct = 0, magnitudeA = 0, magnitudeB = 0;

    for (int i = 0; i < minLength; i++) {
      dotProduct += vectorA[i] * vectorB[i];
      magnitudeA += vectorA[i] * vectorA[i];
      magnitudeB += vectorB[i] * vectorB[i];
    }

    magnitudeA = sqrt(magnitudeA);
    magnitudeB = sqrt(magnitudeB);

    return magnitudeA == 0 || magnitudeB == 0 ? 0.0 : dotProduct / (magnitudeA * magnitudeB);
  }

  // Start real-time comparison every 0.5 seconds
  Future<void> _startRealTimeComparison() async {
    if (_sampleMFCC == null) return;

    if (_isComparing) return; // Prevent multiple timers

    setState(() {
      _isComparing = true;
    });

    // Ensure recorder is ready
    if (_recorder == null) {
      _recorder = FlutterSoundRecorder();
      await _recorder!.openRecorder();
    }

    // Start the timer for real-time comparison
    _timer = Timer.periodic(const Duration(milliseconds: 6000), (timer) async {
      if (!_isComparing) {
        timer.cancel();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final realTimeFilePath = '${tempDir.path}/real_time_suara.aac';

      // Ensure previous recording has stopped
      if (_recorder!.isRecording) {
        await _recorder!.stopRecorder();
      }

      // Start recorder
      await _recorder!.startRecorder(
        toFile: realTimeFilePath,
        codec: Codec.aacADTS,
      );

      // Record for 0.5 seconds
      await Future.delayed(const Duration(milliseconds: 5000));

      // Stop recorder
      await _recorder!.stopRecorder();

      // Extract waveform and compute MFCC from real-time voice
      String pcmPath = await _extractWaveform(realTimeFilePath);
      final audioBytes = await _getAudioBytes(pcmPath);
      var realTimeMFCC = computeMFCC(audioBytes, 16000, 13);

      // Compute similarity with sample
      double similarity = cosineSimilarity(_sampleMFCC!, realTimeMFCC);
      setState(() {
        _similarity = similarity * 100; // In percentage
        _comparisonResult = "Kemiripan: ${_similarity.toStringAsFixed(2)}%";
      });
    });
  }

  // Stop real-time comparison
  void _stopRealTimeComparison() async {
    if (_timer != null) {
      _timer!.cancel();
      _timer = null;
    }

    if (_recorder != null && _recorder!.isRecording) {
      await _recorder!.stopRecorder();
    }

    setState(() {
      _isComparing = false;
      _comparisonResult = "Perbandingan real-time dihentikan.";
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Comparison'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Rekam suara sample, lalu mulai perbandingan real-time"),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isRecording ? null : _recordSample,
              child: const Text("Rekam Sample Suara (5 Detik)"),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: (_sampleMFCC == null || _isComparing) ? null : _startRealTimeComparison,
              child: const Text("Mulai Perbandingan Real-Time"),
            ),
            ElevatedButton(
              onPressed: _isComparing ? _stopRealTimeComparison : null,
              child: const Text("Berhenti Perbandingan Real-Time"),
            ),
            const SizedBox(height: 20),
            Text(
              _comparisonResult,
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}