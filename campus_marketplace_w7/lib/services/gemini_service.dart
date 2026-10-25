import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = 'gemini-flash-lite-latest';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  Future<String> generateText(String prompt) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ไม่พบ Gemini API Key กรุณาระบุผ่าน --dart-define=GEMINI_API_KEY=your_key ตอนรัน',
      );
    }

    final uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ]
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception(
            'AI ไม่สามารถสร้างเนื้อหาได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม',
          );
        }

        final candidate = candidates[0] as Map<String, dynamic>;
        final finishReason = candidate['finishReason'] as String?;
        if (finishReason == 'SAFETY') {
          throw Exception(
            'เนื้อหาที่ประมวลผลเข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini',
          );
        }

        final content = candidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) {
          throw Exception('ไม่พบเนื้อหาในคำตอบจาก Gemini');
        }

        final text = parts[0]['text'] as String?;
        return text ?? '';
      } else if (response.statusCode == 400) {
        throw Exception('คำขอไม่ถูกต้องหรือ API Key ไม่ถูกต้อง (400)');
      } else if (response.statusCode == 403) {
        throw Exception('ถูกปฏิเสธสิทธิ์การเข้าถึง ตรวจสอบ API Key (403)');
      } else if (response.statusCode == 404) {
        throw Exception('ไม่พบโมเดลที่เรียกใช้ ($_model) (404)');
      } else if (response.statusCode == 429) {
        throw Exception('ใช้งานเกินโควตาที่กำหนด กรุณารอสักครู่แล้วลองใหม่ (429)');
      } else if (response.statusCode == 503) {
        throw Exception('เซิร์ฟเวอร์ Gemini กำลังทำงานหนัก กรุณาลองใหม่อีกครั้ง (503)');
      } else {
        throw Exception(
          'เกิดข้อผิดพลาดในการเรียกใช้ Gemini API: สถานะ ${response.statusCode}',
        );
      }
    } on TimeoutException {
      throw Exception(
        'การเชื่อมต่อ Gemini API หมดเวลา (20 วินาที) กรุณาลองใหม่อีกครั้ง',
      );
    } on http.ClientException {
      throw Exception(
        'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ',
      );
    } on FormatException {
      throw Exception('ข้อมูลที่ได้รับจาก Gemini ไม่ถูกต้อง');
    } catch (e) {
      rethrow;
    }
  }
}
