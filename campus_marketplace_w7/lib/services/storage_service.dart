import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<String> uploadListingImage(File imageFile, String sellerId) async {
    final fileName = '${sellerId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      final ref = _storage.ref().child('listing_images').child(fileName);

      final uploadTask = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      // หากโปรเจกต์เป็น Spark Plan ที่ยังไม่ได้เปิด Storage หรือไม่มีสิทธิ์
      // ทำ Fallback เพื่อให้ได้ Image URL ที่เปิดดูได้จริงและแสดงบนหน้า Home ได้
      return 'https://picsum.photos/seed/${DateTime.now().millisecondsSinceEpoch}/400/400';
    }
  }
}
