import 'dart:io';
import 'dart:convert';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

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

  /// Extract text from PDF file - aggressive raw extraction
  Future<String> _extractFromPdf(File file) async {
    print('📖 Reading PDF file...');
    try {
      final bytes = await file.readAsBytes();
      print('📖 PDF file size: ${bytes.length} bytes');

      // Strategy 1: Try Latin1 decoding (most PDF text is Latin1)
      String result = latin1.decode(bytes, allowInvalid: true);

      print('📊 Latin1 decoded: ${result.length} characters');

      // Check for tokens immediately in raw text
      var hasTokens = _checkForTokens(result);
      print('📊 Initial token check: $hasTokens');

      if (!hasTokens['any']!) {
        // Strategy 2: Try UTF-8 decoding
        print('⚠️ Trying UTF-8 decoding...');
        try {
          result = utf8.decode(bytes, allowMalformed: true);
          hasTokens = _checkForTokens(result);
          print('📊 UTF-8 token check: $hasTokens');
        } catch (e) {
          print('⚠️ UTF-8 failed: $e');
        }
      }

      // Strategy 3: Look for tokens in hex patterns
      if (!hasTokens['any']!) {
        print('⚠️ Looking for hex-encoded tokens...');
        // In PDF, text might be hex-encoded
        final hexPlusPattern = RegExp(r'2B\s*2B\s*2B\s*2B\s*2B', caseSensitive: false);
        final hexEqualsPattern = RegExp(r'3D\s*3D\s*3D\s*3D\s*3D', caseSensitive: false);

        if (result.contains(hexPlusPattern) || result.contains(hexEqualsPattern)) {
          print('✅ Found hex-encoded tokens, converting...');
          result = _decodeHexTokens(result);
          hasTokens = _checkForTokens(result);
          print('📊 After hex decode: $hasTokens');
        }
      }

      // Clean up PDF artifacts while preserving our tokens
      result = _cleanPdfArtifacts(result);

      // Final check
      hasTokens = _checkForTokens(result);
      print('📊 Final token check: $hasTokens');

      if (!hasTokens['any']!) {
        // Last resort: try to find any pattern that looks like our format
        print('⚠️ No tokens found. Checking for alternative patterns...');

        // Look for repeated characters that might be our tokens
        if (result.contains(RegExp(r'\+{5}')) ||
            result.contains(RegExp(r'={5}')) ||
            result.contains(RegExp(r'\+ {5}'))) {
          print('✅ Found token-like patterns');
          result = result.replaceAll(RegExp(r'\+\s+\+\s+\+\s+\+\s+\+'), '+++++');
          result = result.replaceAll(RegExp(r'=\s+=\s+=\s+=\s+='), '=====');
        } else {
          throw Exception(
              'PDF does not contain quiz format markers (+++++ or =====). '
                  'The PDF may be using an unsupported encoding. '
                  'Please save your quiz as TXT or DOCX format for guaranteed compatibility.'
          );
        }
      }

      print('📖 PDF extracted: ${result.length} characters');
      return result;

    } catch (e) {
      if (e.toString().contains('quiz format')) {
        rethrow;
      }
      throw Exception(
          'Failed to parse PDF: $e. '
              'For best results, save your quiz as TXT or DOCX format.'
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

  /// Decode hex-encoded tokens in PDF
  String _decodeHexTokens(String text) {
    // + = 2B in hex, = = 3D in hex, # = 23 in hex
    var result = text;

    // Decode hex sequences
    result = result.replaceAllMapped(
      RegExp(r'2B\s*2B\s*2B\s*2B\s*2B', caseSensitive: false),
          (match) => '+++++',
    );
    result = result.replaceAllMapped(
      RegExp(r'3D\s*3D\s*3D\s*3D\s*3D', caseSensitive: false),
          (match) => '=====',
    );

    return result;
  }

  /// Clean PDF artifacts while preserving tokens
  String _cleanPdfArtifacts(String text) {
    var result = text;

    // Remove PDF-specific patterns but be careful not to remove our tokens
    final patterns = [
      RegExp(r'%PDF-[\d.]+'),
      RegExp(r'%%EOF'),
      RegExp(r'/Type\s*/\w+'),
      RegExp(r'/Filter\s*/\w+'),
      RegExp(r'/Length\s+\d+'),
      RegExp(r'/Size\s+\d+'),
      RegExp(r'\d+\s+\d+\s+obj\b'),
      RegExp(r'\bendobj\b'),
      RegExp(r'\bxref\b'),
      RegExp(r'\btrailer\b'),
      RegExp(r'\bstartxref\b'),
    ];

    for (final pattern in patterns) {
      result = result.replaceAll(pattern, ' ');
    }

    // Fix spaced tokens
    result = result.replaceAll(RegExp(r'\+\s+\+\s+\+\s+\+\s+\+'), '+++++');
    result = result.replaceAll(RegExp(r'=\s+=\s+=\s+=\s+='), '=====');

    // Clean up whitespace
    result = result.replaceAll(RegExp(r' {2,}'), ' ');
    result = result.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n');

    return result.trim();
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

      // Extract text between <w:t> tags (simplified XML parsing)
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