import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ffmpeg_kit_https_flutter/ffmpeg_kit.dart';

import 'package:docx_template/docx_template.dart';

void main() {
  runApp(const A2TApp());
}

class A2TApp extends StatelessWidget {
  const A2TApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio → Text',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  File? _inputFile;
  String _status = 'Ожидание';
  double _progress = 0;
  bool _busy = false;

  final List<_LangItem> _langs = const [
    _LangItem('Русский', 'ru-RU'),
    _LangItem('English', 'en-US'),
    _LangItem('عربي', 'ar-SA'),
  ];
  _LangItem _selected = const _LangItem('Русский', 'ru-RU');

  final List<String> _logLines = [];

  void _log(String s) {
    setState(() {
      _logLines.add(s);
      _status = s;
    });
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'wav','mp3','ogg','opus','flac','m4a','aac','wma',
        'mp4','mov','mkv','avi','webm'
      ],
    );
    if (res == null || res.files.single.path == null) return;

    setState(() {
      _inputFile = File(res.files.single.path!);
      _logLines.clear();
      _status = 'Файл выбран: ${_inputFile!.path}';
    });
  }

  Future<void> _ensurePermissions() async {
    // Для Android 11 обычно достаточно:
    // - микрофон (если будешь писать аудио)
    // - доступ к файлам (file picker часто работает без, но лучше проверить)
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  Future<String> _convertToWav(File input) async {
    final tmpDir = await getTemporaryDirectory();
    final wavPath = '${tmpDir.path}/a2t_${DateTime.now().millisecondsSinceEpoch}.wav';

    // 16kHz mono PCM — удобно для speech
    final cmd = '-y -i "${input.path}" -ac 1 -ar 16000 -c:a pcm_s16le "$wavPath"';
    _log('FFmpeg: конвертация в WAV...');
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();

    if (rc == null || !rc.isValueSuccess()) {
      throw Exception('FFmpeg failed: ${await session.getFailStackTrace()}');
    }
    return wavPath;
  }

  Future<void> _createDocx(String text, String baseName) async {
    final docsDir = await getExternalStorageDirectory();
    if (docsDir == null) throw Exception('Нет доступа к папке сохранения');

    // Шаблон docx можно сделать отдельным файлом, но для простоты сделаем "пустой" docx из assets позже.
    // Сейчас создадим docx через docx_template:
    // Нужно положить шаблон в assets: assets/template.docx
    final bytes = await File('assets/template.docx').readAsBytes(); // временно
    final docx = await DocxTemplate.fromBytes(bytes);

    final content = Content();
    content.add(TextContent('body', text));

    final out = await docx.generate(content);
    if (out == null) throw Exception('Не удалось собрать docx');

    final outPath = '${docsDir.path}/$baseName.docx';
    await File(outPath).writeAsBytes(out);
    _log('DOCX сохранён: $outPath');
  }

  Future<void> _start() async {
    if (_inputFile == null || _busy) return;

    setState(() {
      _busy = true;
      _progress = 0;
      _logLines.clear();
      _status = 'Старт...';
    });

    try {
      await _ensurePermissions();

      final wavPath = await _convertToWav(_inputFile!);
      setState(() => _progress = 0.25);

      // TODO: тут будет распознавание (сегменты, язык, дублирование хвоста)
      // Сейчас просто заглушка:
      final recognizedText = 'TODO: распознавание речи. Язык: ${_selected.code}\nWAV: $wavPath';
      _log('Распознавание: (пока заглушка)');
      setState(() => _progress = 0.75);

      final baseName = File(_inputFile!.path).uri.pathSegments.last.split('.').first;
      await _createDocx(recognizedText, baseName);
      setState(() => _progress = 1.0);

      _log('Готово.');
    } catch (e) {
      _log('Ошибка: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Преобразование аудио в текст')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _busy ? null : _pickFile,
              child: Text(_inputFile == null ? 'Выбрать файл (аудио/видео)' : 'Файл: ${_inputFile!.path}'),
            ),
            const SizedBox(height: 12),
            const Text('Выберите язык распознавания:'),
            DropdownButton<_LangItem>(
              value: _selected,
              items: _langs
                  .map((x) => DropdownMenuItem(value: x, child: Text(x.name)))
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _selected = v!),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _busy ? _progress : null),
            const SizedBox(height: 8),
            Text('Статус: $_status'),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _logLines.length,
                  itemBuilder: (_, i) => SelectableText(_logLines[i]),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_inputFile == null || _busy) ? null : _start,
              child: const Text('Преобразовать'),
            ),
            const SizedBox(height: 8),
            const Text(
              'solvo.center | 7497299@mail.ru | DzarmotovBI (Дзармотов Б.И.)',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangItem {
  final String name;
  final String code;
  const _LangItem(this.name, this.code);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _LangItem && name == other.name && code == other.code;

  @override
  int get hashCode => Object.hash(name, code);
}
