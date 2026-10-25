import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../models/listing_draft.dart';

class GeminiVisionService {
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _model = 'gemini-flash-lite-latest';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  Future<ListingDraft> analyzeProductImage(
    Uint8List imageBytes,
    String prompt, {
    String mimeType = 'image/jpeg',
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception(
        'ไม่พบ Gemini API Key กรุณาระบุผ่าน --dart-define=GEMINI_API_KEY=your_key ตอนรัน',
      );
    }

    final base64Image = base64Encode(imageBytes);

    final uri = Uri.parse('$_baseUrl/$_model:generateContent?key=$_apiKey');

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'inlineData': {
                'mimeType': mimeType,
                'data': base64Image,
              }
            },
            {
              'text': prompt,
            }
          ]
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'title': {'type': 'STRING'},
            'category': {'type': 'STRING'},
            'description': {'type': 'STRING'},
          },
          'required': ['title', 'category', 'description'],
        },
      }
    });

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;

        if (candidates == null || candidates.isEmpty) {
          throw Exception(
            'AI ไม่สามารถวิเคราะห์ภาพนี้ได้ อาจเข้าข่ายเนื้อหาที่ไม่เหมาะสม ลองใช้ภาพอื่น',
          );
        }

        final candidate = candidates[0] as Map<String, dynamic>;
        final finishReason = candidate['finishReason'] as String?;
        if (finishReason == 'SAFETY') {
          throw Exception(
            'เนื้อหาที่วิเคราะห์เข้าข่ายไม่ปลอดภัยตามนโยบายของ Gemini กรุณาใช้ภาพอื่น',
          );
        }

        final content = candidate['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) {
          throw Exception('ไม่พบเนื้อหาในผลการวิเคราะห์จาก Gemini');
        }

        final text = parts[0]['text'] as String?;
        if (text == null || text.isEmpty) {
          throw Exception('ผลลัพธ์จาก AI ว่างเปล่า');
        }

        final Map<String, dynamic> jsonResult = jsonDecode(text);
        return ListingDraft.fromJson(jsonResult);
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
        'การเชื่อมต่อ Gemini API หมดเวลา กรุณาลองใหม่อีกครั้ง',
      );
    } on http.ClientException {
      throw Exception(
        'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบการเชื่อมต่อ',
      );
    } on FormatException {
      throw Exception('ข้อมูล JSON ที่ได้รับจาก Gemini ไม่ถูกต้อง');
    } catch (e) {
      rethrow;
    }
  }
}
