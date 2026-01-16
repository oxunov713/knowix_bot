import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

/// Improved text extractor service for DOCX, DOC, TXT files
class FileTextExtractorService {
  /// Extract text from file based on extension
  Future<String> extractText(File file) async {
    final extension = path.extension(file.path).toLowerCase();

    try {
      switch (extension) {
        case '.txt':
          return await _extractFromTxt(file);
        case '.doc':
        case '.docx':
          return await _extractFromDocx(file);
        default:
          throw UnsupportedError('Qo\'llab-quvvatlanmaydigan fayl turi: $extension\n\n'
              '📄 Faqat quyidagi formatlar qo\'llab-quvvatlanadi:\n'
              '   • DOCX (tavsiya etiladi) ✅\n'
              '   • DOC\n'
              '   • TXT');
      }
    } catch (e) {
      throw Exception('Fayldan matn ajratishda xatolik: $e');
    }
  }

  /// Extract text from TXT file
  Future<String> _extractFromTxt(File file) async {
    print('📖 TXT fayl o\'qilmoqda...');

    // Try multiple encodings
    final List<Encoding> encodings = [
      utf8,
      latin1,
      Encoding.getByName('windows-1251') ?? latin1,
      Encoding.getByName('cp866') ?? latin1,
      Encoding.getByName('koi8-r') ?? latin1,
    ];

    for (final encoding in encodings) {
      try {
        final text = await file.readAsString(encoding: encoding);
        if (text.isNotEmpty && !_hasGarbledText(text)) {
          print('📖 TXT fayl o\'qildi (${encoding.name}): ${text.length} belgi');
          return text;
        }
      } catch (e) {
        continue;
      }
    }

    throw Exception('TXT faylni hech qanday kodlashda o\'qib bo\'lmadi');
  }

  /// Check if text contains garbled/corrupted characters
  bool _hasGarbledText(String text) {
    if (text.length < 100) return false;

    // Count weird characters
    int weirdChars = 0;
    for (int i = 0; i < text.length && i < 500; i++) {
      final code = text.codeUnitAt(i);
      // ASCII control chars (except newline, tab, carriage return)
      if ((code < 32 && code != 10 && code != 13 && code != 9) ||
          // Replacement character
          code == 65533 ||
          // Private use area
          (code >= 57344 && code <= 63743)) {
        weirdChars++;
      }
    }

    return weirdChars > text.length * 0.1;
  }

  /// Extract text from DOCX file - COMPREHENSIVE METHOD
  Future<String> _extractFromDocx(File file) async {
    print('📖 DOCX fayl o\'qilmoqda...');

    try {
      final bytes = await file.readAsBytes();
      print('📖 DOCX fayl hajmi: ${bytes.length} bayt');

      // Decode ZIP archive
      final archive = ZipDecoder().decodeBytes(bytes);
      print('📖 ZIP arxiv ochildi: ${archive.files.length} ta fayl');

      // Find main document
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        throw Exception('DOCX strukturasi noto\'g\'ri: word/document.xml topilmadi');
      }

      // Decode XML
      final xmlContent = utf8.decode(documentFile.content as List<int>);
      print('📖 XML hajmi: ${xmlContent.length} belgi');

      // Parse XML
      final document = xml.XmlDocument.parse(xmlContent);

      // Extract text using MULTIPLE methods for best coverage
      final methods = [
        _extractViaParagraphs,
        _extractViaTextNodes,
        _extractViaAllElements,
      ];

      String bestResult = '';
      int bestScore = 0;

      for (final method in methods) {
        try {
          final result = method(document);
          final score = _scoreExtractedText(result);

          print('📖 Usul natijasi: ${result.length} belgi, skor: $score');

          if (score > bestScore) {
            bestScore = score;
            bestResult = result;
          }
        } catch (e) {
          print('⚠️ Usul xatolik: $e');
        }
      }

      if (bestResult.isEmpty) {
        throw Exception('DOCX fayldan matn ajratib bo\'lmadi');
      }

      print('✅ DOCX\'dan ajratildi: ${bestResult.length} belgi');
      return bestResult;

    } catch (e) {
      print('❌ DOCX xatolik: $e');
      throw Exception('DOCX faylni tahlil qilishda xatolik: ${e.toString()}');
    }
  }

  /// Method 1: Extract via paragraphs (standard approach)
  String _extractViaParagraphs(xml.XmlDocument document) {
    final buffer = StringBuffer();
    final paragraphs = document.findAllElements('w:p');

    for (final paragraph in paragraphs) {
      final paragraphText = _extractTextFromParagraph(paragraph);
      if (paragraphText.isNotEmpty) {
        buffer.writeln(paragraphText);
      }
    }

    return buffer.toString().trim();
  }

  /// Method 2: Extract via all text nodes
  String _extractViaTextNodes(xml.XmlDocument document) {
    final buffer = StringBuffer();
    final textElements = document.findAllElements('w:t');

    String currentLine = '';
    xml.XmlElement? lastParent;

    for (final textElement in textElements) {
      final text = textElement.innerText;

      // Detect paragraph breaks
      final currentParent = _findParentParagraph(textElement);
      if (currentParent != lastParent && currentLine.isNotEmpty) {
        buffer.writeln(currentLine.trim());
        currentLine = '';
      }

      currentLine += text;
      lastParent = currentParent;
    }

    if (currentLine.isNotEmpty) {
      buffer.writeln(currentLine.trim());
    }

    return buffer.toString().trim();
  }

  /// Method 3: Extract all text content (aggressive)
  String _extractViaAllElements(xml.XmlDocument document) {
    final lines = <String>[];
    final paragraphs = document.findAllElements('w:p');

    for (final paragraph in paragraphs) {
      final runs = paragraph.findElements('w:r');
      final lineBuffer = StringBuffer();

      for (final run in runs) {
        final textElements = run.findElements('w:t');
        for (final textElement in textElements) {
          final text = textElement.innerText.trim();
          if (text.isNotEmpty) {
            lineBuffer.write(text);
          }
        }

        // Handle tabs and breaks
        if (run.findElements('w:tab').isNotEmpty) {
          lineBuffer.write(' ');
        }
        if (run.findElements('w:br').isNotEmpty) {
          final currentLine = lineBuffer.toString().trim();
          if (currentLine.isNotEmpty) {
            lines.add(currentLine);
            lineBuffer.clear();
          }
        }
      }

      final line = lineBuffer.toString().trim();
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }

    return lines.join('\n');
  }

  /// Extract text from a paragraph element
  String _extractTextFromParagraph(xml.XmlElement paragraph) {
    final buffer = StringBuffer();

    // Get all text elements
    final textElements = paragraph.findAllElements('w:t');

    for (final textElement in textElements) {
      final text = textElement.innerText;
      if (text.isNotEmpty) {
        buffer.write(text);
      }
    }

    // Handle tabs
    final tabs = paragraph.findElements('w:tab').length;
    if (tabs > 0) {
      buffer.write(' ' * tabs);
    }

    return buffer.toString().trim();
  }

  /// Find parent paragraph of an element
  xml.XmlElement? _findParentParagraph(xml.XmlElement element) {
    xml.XmlNode? current = element.parent;

    while (current != null) {
      if (current is xml.XmlElement && current.name.local == 'p') {
        return current;
      }
      current = current.parent;
    }

    return null;
  }

  /// Score extracted text quality
  int _scoreExtractedText(String text) {
    if (text.isEmpty) return 0;

    int score = text.length; // Base score: length

    // Bonus for quiz format markers
    if (RegExp(r'\+{4,}').hasMatch(text)) score += 1000;
    if (RegExp(r'={4,}').hasMatch(text)) score += 1000;
    if (text.contains('#')) score += 500;

    // Bonus for question marks
    score += '?'.allMatches(text).length * 100;

    // Bonus for Cyrillic text (Uzbek/Russian)
    final cyrillicChars = text.codeUnits.where((c) => c >= 1040 && c <= 1103).length;
    score += cyrillicChars * 2;

    // Penalty for very long lines (might be corrupted)
    final lines = text.split('\n');
    final longLines = lines.where((line) => line.length > 500).length;
    score -= longLines * 100;

    // Penalty for too many weird characters
    final weirdChars = text.codeUnits.where((c) =>
    c < 32 && c != 10 && c != 13 && c != 9
    ).length;
    score -= weirdChars * 10;

    return score;
  }

  /// Check if file type is supported
  bool isSupportedFileType(String filename) {
    final extension = path.extension(filename).toLowerCase();
    return ['.txt', '.doc', '.docx'].contains(extension);
  }

  /// Estimate question count in text
  int countQuestions(String text) {
    if (text.isEmpty) return 0;

    final questionMarkers = RegExp(r'\+{4,}').allMatches(text).length;
    return questionMarkers;
  }
}