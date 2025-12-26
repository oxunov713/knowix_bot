import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:xml/xml.dart' as xml;

/// Turli fayl formatlaridan matn ajratib oluvchi yaxshilangan servis
/// PDF qo'llab-quvvatlanmaydi - faqat DOCX, DOC, TXT
class FileTextExtractorService {
  /// Fayl kengaytmasiga qarab matn ajratish
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

  /// TXT fayldan matn ajratish
  Future<String> _extractFromTxt(File file) async {
    print('📖 TXT fayl o\'qilmoqda...');

    // Turli kodlashlarni sinab ko'rish
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
        if (text.isNotEmpty) {
          print('📖 TXT fayl o\'qildi (${encoding.name}): ${text.length} belgi');
          return text;
        }
      } catch (e) {
        continue;
      }
    }

    throw Exception('TXT faylni hech qanday kodlashda o\'qib bo\'lmadi');
  }

  /// DOCX fayldan matn ajratish - to'liq yaxshilangan usul
  Future<String> _extractFromDocx(File file) async {
    print('📖 DOCX fayl o\'qilmoqda...');

    try {
      final bytes = await file.readAsBytes();
      print('📖 DOCX fayl hajmi: ${bytes.length} bayt');

      // ZIP arxivini ochish
      final archive = ZipDecoder().decodeBytes(bytes);

      // Asosiy dokument faylini topish
      final documentFile = archive.findFile('word/document.xml');
      if (documentFile == null) {
        throw Exception('DOCX fayl strukturasi noto\'g\'ri: word/document.xml topilmadi');
      }

      // XML ni o'qish
      final xmlContent = utf8.decode(documentFile.content as List<int>);

      // XML ni parse qilish
      final document = xml.XmlDocument.parse(xmlContent);

      // Barcha matn elementlarini yig'ish - YANGILANGAN USUL
      final buffer = StringBuffer();

      // <w:p> (paragraph) elementlarini qidirish
      final paragraphs = document.findAllElements('w:p');

      print('📖 Topilgan paragraflar: ${paragraphs.length}');

      for (final paragraph in paragraphs) {
        final paragraphText = _extractTextFromParagraph(paragraph);
        if (paragraphText.isNotEmpty) {
          buffer.writeln(paragraphText);
        }
      }

      String result = buffer.toString().trim();

      // Agar paragraflar bo'yicha kam matn topilsa, alternativ usul
      if (result.length < 500 || !_containsQuizFormat(result)) {
        print('📖 Asosiy usul kam natija berdi, qo\'shimcha usullarni ishlatamiz...');
        final alternativeResult = _extractAllTextElements(document);

        // Eng yaxshi natijani tanlash
        if (alternativeResult.length > result.length) {
          result = alternativeResult;
        }
      }

      print('📖 DOCX\'dan ajratildi: ${result.length} belgi');

      if (result.isEmpty) {
        throw Exception('DOCX fayldan matn ajratib bo\'lmadi');
      }

      // Test formatini tekshirish
      if (!_containsQuizFormat(result)) {
        print('⚠️ Ogohlik: DOCX faylda HEMIS test formati aniq emas');
      }

      return result;

    } catch (e) {
      print('❌ DOCX xatolik: $e');
      throw Exception('DOCX faylni tahlil qilishda xatolik: ${e.toString()}');
    }
  }

  /// Paragrafdan matn ajratish - yaxshilangan
  String _extractTextFromParagraph(xml.XmlElement paragraph) {
    final buffer = StringBuffer();

    // Barcha <w:t> elementlarini topish
    final textElements = paragraph.findAllElements('w:t');

    for (final textElement in textElements) {
      final text = textElement.innerText;
      if (text.isNotEmpty) {
        buffer.write(text);
      }
    }

    // Barcha <w:tab/> elementlarini bo'sh joy bilan almashtirish
    if (paragraph.findElements('w:tab').isNotEmpty) {
      buffer.write(' ');
    }

    return buffer.toString().trim();
  }

  /// Barcha matn elementlarini ajratish - to'liq usul
  String _extractAllTextElements(xml.XmlDocument document) {
    final buffer = StringBuffer();
    final lines = <String>[];

    // Barcha paragraflarni qayta ishlash
    final paragraphs = document.findAllElements('w:p');

    for (final paragraph in paragraphs) {
      final lineBuffer = StringBuffer();

      // Paragraf ichidagi barcha runs (w:r)
      final runs = paragraph.findElements('w:r');

      for (final run in runs) {
        // Har bir run ichidagi matn
        final textElements = run.findElements('w:t');
        for (final textElement in textElements) {
          final text = textElement.innerText.trim();
          if (text.isNotEmpty) {
            lineBuffer.write(text);
          }
        }

        // Tab va boshqa bo'sh joylar
        if (run.findElements('w:tab').isNotEmpty) {
          lineBuffer.write(' ');
        }
      }

      final line = lineBuffer.toString().trim();
      if (line.isNotEmpty) {
        lines.add(line);
      }
    }

    // Barcha qatorlarni birlashtirish
    return lines.join('\n');
  }

  /// Matnda test formati borligini tekshirish
  bool _containsQuizFormat(String text) {
    if (text.length < 100) return false;

    // HEMIS test formatini qidirish
    final patterns = [
      RegExp(r'\+{4,5}'),  // ++++ yoki +++++
      RegExp(r'={4,5}'),   // ==== yoki =====
      RegExp(r'#'),        // To'g'ri javob belgisi
      RegExp(r'\?'),       // Savol belgisi
      RegExp(r'[A-Da-d][\)\.]'), // Variantlar: A) B) C) D) yoki A. B. C. D.
    ];

    int matches = 0;
    for (final pattern in patterns) {
      if (pattern.hasMatch(text)) {
        matches++;
      }
    }

    return matches >= 2;
  }

  /// Fayl turi qo'llab-quvvatlanadimi
  bool isSupportedFileType(String filename) {
    final extension = path.extension(filename).toLowerCase();
    return ['.txt', '.doc', '.docx'].contains(extension);
  }

  /// Savollar sonini taxminiy hisoblash
  int countQuestions(String text) {
    if (text.isEmpty) return 0;

    // HEMIS formatidagi savol ajratuvchilari
    final questionSeparators = [
      RegExp(r'\+{4,5}'),
      RegExp(r'\n\s*\n'), // Bo'sh qatorlar
    ];

    int maxCount = 0;
    for (final separator in questionSeparators) {
      final count = separator.allMatches(text).length;
      if (count > maxCount) {
        maxCount = count;
      }
    }

    return maxCount;
  }
}