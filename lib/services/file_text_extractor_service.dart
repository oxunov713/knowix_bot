import 'dart:io';
import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Service for extracting text from various file formats
class FileTextExtractorService {
  /// Extract text from a file based on its extension
  Future<String> extractText(File file) async {
    final extension = path.extension(file.path).toLowerCase();

    try {
      switch (extension) {
        case '.txt':
          return await _extractFromTxt(file);
        case '.pdf':
          return await _extractFromPdf(file);
        case '.doc':
        case '.docx':
          return await _extractFromDocx(file);
        default:
          throw UnsupportedError('Unsupported file type: $extension');
      }
    } catch (e) {
      throw Exception('Failed to extract text from file: $e');
    }
  }

  /// Extract text from TXT file
  Future<String> _extractFromTxt(File file) async {
    print('📖 Reading TXT file...');
    final text = await file.readAsString();
    print('📖 TXT file read: ${text.length} characters');
    return text;
  }

  /// Extract text from PDF file - Simple approach
  Future<String> _extractFromPdf(File file) async {
    print('📖 Reading PDF file...');
    print('⚠️ PDF matn ajratish cheklangan. TXT yoki DOCX format tavsiya etiladi.');

    try {
      final bytes = await file.readAsBytes();
      print('📖 PDF file size: ${bytes.length} bytes');

      // Try to extract text using simple string search
      // This works for simple, uncompressed PDFs
      String rawText = latin1.decode(bytes, allowInvalid: true);

      // Look for text streams in PDF
      final streamPattern = RegExp(r'stream\s*(.*?)\s*endstream', dotAll: true);
      final matches = streamPattern.allMatches(rawText);

      final buffer = StringBuffer();
      for (final match in matches) {
        final streamContent = match.group(1) ?? '';
        // Try to extract readable text
        final readable = streamContent.replaceAll(RegExp(r'[^\x20-\x7E\n\r]+'), ' ');
        if (readable.length > 10) {
          buffer.write(readable);
          buffer.write('\n');
        }
      }

      String result = buffer.toString();

      // If no streams found, try direct text extraction
      if (result.isEmpty || result.length < 100) {
        print('⚠️ Stream extraction failed, trying direct extraction...');
        result = rawText.replaceAll(RegExp(r'[^\x20-\x7E\n\r]+'), ' ');
      }

      // Clean up
      result = result.replaceAll(RegExp(r'\s+'), ' ');
      result = result.replaceAll(RegExp(r'[<>(){}\[\]\/\\]'), '');

      print('📖 PDF extracted: ${result.length} characters');

      // Check for quiz markers
      final hasTokens = _checkForTokens(result);
      print('📊 Token check: $hasTokens');

      if (!hasTokens['any']!) {
        throw Exception(
            '❌ PDF formatdan matn ajratib bo\'lmadi.\n\n'
                '📝 Iltimos, faylni quyidagi formatlarda yuboring:\n'
                '   • TXT format (.txt) - eng yaxshi variant\n'
                '   • DOCX format (.docx) - ishonchli\n\n'
                '🔄 PDF ni TXT ga o\'girish:\n'
                '1. PDF ni Word da oching (yoki Adobe Reader)\n'
                '2. "Save As" → "Plain Text (.txt)" tanlang\n'
                '3. Saqlang va qayta yuboring'
        );
      }

      return result;

    } catch (e) {
      if (e.toString().contains('PDF formatdan')) {
        rethrow;
      }
      throw Exception(
          '❌ PDF ishlov berishda xatolik: $e\n\n'
              '💡 Yechim: Faylni TXT yoki DOCX formatda saqlang va qayta yuboring.'
      );
    }
  }

  /// Check for presence of quiz tokens
  Map<String, bool> _checkForTokens(String text) {
    final hasQuestion = text.contains('+++++') || text.contains('+ + + + +');
    final hasOption = text.contains('=====') || text.contains('= = = = =');
    final hasCorrect = text.contains('#');

    return {
      'question': hasQuestion,
      'option': hasOption,
      'correct': hasCorrect,
      'any': hasQuestion || hasOption || hasCorrect,
    };
  }

  /// Extract text from DOCX file using archive package
  Future<String> _extractFromDocx(File file) async {
    print('📖 Reading DOCX file...');
    try {
      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find document.xml which contains the text
      final documentXml = archive.findFile('word/document.xml');

      if (documentXml == null) {
        throw Exception('Invalid DOCX file structure');
      }

      final content = String.fromCharCodes(documentXml.content as List<int>);

      // Extract text between <w:t> tags
      final textPattern = RegExp(r'<w:t[^>]*>([^<]*)</w:t>');
      final matches = textPattern.allMatches(content);

      final buffer = StringBuffer();
      for (final match in matches) {
        if (match.group(1) != null) {
          buffer.write(match.group(1));
          buffer.write(' ');
        }
      }

      final result = buffer.toString().trim();
      print('📖 DOCX extracted: ${result.length} characters');
      return result;
    } catch (e) {
      throw Exception('Failed to parse DOCX: $e');
    }
  }

  /// Check if file type is supported
  bool isSupportedFileType(String filename) {
    final extension = path.extension(filename).toLowerCase();
    return ['.txt', '.pdf', '.doc', '.docx'].contains(extension);
  }
}