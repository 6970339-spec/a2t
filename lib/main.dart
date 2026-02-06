import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:docx_template/docx_template.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const A2TApp());
}

class A2TApp extends StatelessWidget {
  const A2TApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'A2T - Аудио в текст',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const A2THomePage(),
    );
  }
}

class A2THomePage extends StatefulWidget {
  const A2THomePage({super.key});

  @override
  State<A2THomePage> createState() => _A2THomePageState();
}

class _A2THomePageState extends State<A2THomePage> {
  static const String buildLabel = 'BUILD: 2026-01-22 05';

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordElapsedSec = 0;
  Timer? _recordTimer;

  final TextEditingController _textCtrl = TextEditingController();
  double _progress = 0.0;
  String _status = 'Нажмите "Запись" для начала';
  String? _lastDocxPath;

  // Для распознавания речи
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _recorder.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          print('Статус распознавания: $status');
        },
        onError: (error) {
          print('Ошибка распознавания: $error');
        },
      );
      if (_speechAvailable) {
        _setStatus('Распознавание речи готово');
      } else {
        _setStatus('Распознавание речи недоступно');
      }
    } catch (e) {
      _setStatus('Ошибка инициализации: $e');
    }
  }

  void _setStatus(String s) => setState(() => _status = s);
  void _setProgress(double p) => setState(() => _progress = p.clamp(0.0, 1.0));

  void _appendLine(String line) {
    final old = _textCtrl.text;
    _textCtrl.text = old.isEmpty ? line : '$old\n$line';
    _textCtrl.selection = TextSelection.collapsed(offset: _textCtrl.text.length);
  }

  String _mmss(int sec) {
    final mm = sec ~/ 60;
    final ss = sec % 60;
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }

  Future<Directory> _getRecordingsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final folder = Directory('${docs.path}/AudioToText');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<void> _startRecording() async {
    if (_isRecording) return;

    // Запрашиваем разрешения
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _setStatus('Нет разрешения на микрофон');
      return;
    }

    final storageStatus = await Permission.storage.request();
    if (!storageStatus.isGranted) {
      _setStatus('Нет разрешения на хранение');
      return;
    }

    // Проверяем доступность записи
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _setStatus('Нет разрешения на запись');
      return;
    }

    final folder = await _getRecordingsDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final outPath = '${folder.path}/запись_$timestamp.m4a';

    try {
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 16000,
        ),
        path: outPath,
      );

      // Запускаем таймер
      _recordElapsedSec = 0;
      _recordTimer?.cancel();
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _recordElapsedSec += 1);
      });

      setState(() => _isRecording = true);
      _setStatus('Запись...');

      // Начинаем распознавание
      _startListening();
    } catch (e) {
      _setStatus('Ошибка записи: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _recorder.stop();
      _recordTimer?.cancel();

      setState(() => _isRecording = false);

      // Останавливаем распознавание
      _stopListening();

      _setStatus('Запись сохранена');

      if (_lastWords.isNotEmpty) {
        _appendLine('Запись: $_lastWords');
        await _saveResults();
      } else {
        _appendLine('(Распознанный текст отсутствует)');
      }

      _setProgress(1.0);
    } catch (e) {
      _setStatus('Ошибка остановки: $e');
    }
  }

  void _startListening() async {
    if (!_speechAvailable) return;

    try {
      await _speech.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            if (result.finalResult && _lastWords.isNotEmpty) {
              _appendLine(_lastWords);
            }
          });
        },
        localeId: 'ru_RU',
        listenFor: const Duration(minutes: 5),
        pauseFor: const Duration(seconds: 3),
        listenMode: stt.ListenMode.dictation,
      );

      setState(() => _isListening = true);
    } catch (e) {
      print('Ошибка слушания: $e');
    }
  }

  void _stopListening() async {
    try {
      await _speech.stop();
      setState(() => _isListening = false);
    } catch (e) {
      print('Ошибка остановки слушания: $e');
    }
  }

  Future<void> _saveResults() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _setStatus('Нет текста для сохранения');
      return;
    }

    try {
      _setStatus('Сохранение...');

      final folder = await _getRecordingsDir();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final txtPath = '${folder.path}/текст_$timestamp.txt';
      final docxPath = '${folder.path}/текст_$timestamp.docx';

      // Сохраняем как TXT
      final txtFile = File(txtPath);
      await txtFile.writeAsString(text, encoding: utf8);

      // Пытаемся сохранить как DOCX
      try {
        final ByteData data = await rootBundle.load('assets/template.docx');
        final Uint8List bytes = data.buffer.asUint8List();
        final docx = await DocxTemplate.fromBytes(bytes);

        final content = Content();
        content.add(TextContent('content', text));

        final generated = await docx.generate(content);
        if (generated != null) {
          final docxFile = File(docxPath);
          await docxFile.writeAsBytes(generated);
          setState(() => _lastDocxPath = docxPath);
        }
      } catch (e) {
        // Если шаблона нет, просто сохраняем TXT
        print('Не удалось сохранить DOCX: $e');
      }

      _setStatus('Сохранено как TXT и DOCX');
      _setProgress(1.0);
    } catch (e) {
      _setStatus('Ошибка сохранения: $e');
    }
  }

  Future<void> _copyText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      _setStatus('Нет текста для копирования');
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    _setStatus('Текст скопирован');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Текст скопирован в буфер')),
      );
    }
  }

  Future<void> _clearText() async {
    setState(() {
      _textCtrl.clear();
      _progress = 0.0;
      _lastDocxPath = null;
    });
    _setStatus('Текст очищен');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Аудио в текст'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyText,
            tooltip: 'Копировать текст',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearText,
            tooltip: 'Очистить текст',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Статусная строка
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isRecording ? Colors.red[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: _isRecording ? Colors.red : Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _status,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _speechAvailable
                            ? 'Распознавание доступно'
                            : 'Распознавание недоступно',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (_isRecording)
                    Text(
                      _mmss(_recordElapsedSec),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.red,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Кнопки записи
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? null : _startRecording,
                    icon: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      size: 24,
                    ),
                    label: Text(
                      _isRecording ? 'Идет запись...' : 'Начать запись',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRecording ? _stopRecording : null,
                    icon: const Icon(Icons.stop, size: 24),
                    label: const Text(
                      'Остановить',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Индикатор распознавания
            if (_isListening)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.record_voice_over, size: 16, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'Распознавание...',
                      style: TextStyle(color: Colors.green[800]),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Прогресс бар
            LinearProgressIndicator(value: _progress),

            const SizedBox(height: 20),

            // Текстовое поле
            Expanded(
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Распознанный текст:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          readOnly: true,
                          maxLines: null,
                          expands: true,
                          decoration: InputDecoration(
                            hintText: _isListening
                              ? 'Говорите... текст появится здесь автоматически'
                              : 'Нажмите "Начать запись" и говорите',
                            border: InputBorder.none,
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Информация о сохранении
            if (_lastDocxPath != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Файлы сохранены',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'DOCX и TXT файлы созданы',
                            style: TextStyle(color: Colors.grey[700], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Инструкция
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Инструкция:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '1. Нажмите "Начать запись"\n'
                    '2. Говорите четко в микрофон\n'
                    '3. Нажмите "Остановить" для завершения\n'
                    '4. Текст сохранится автоматически',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Подвал
            Text(
              buildLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}