import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../database/app_database.dart';
import '../models/item.dart';
import '../repositories/item_repository_firestore.dart';
import '../repositories/listing_draft_repository.dart';
import '../services/storage_service.dart';

class MyDraftsPage extends StatefulWidget {
  final ListingDraftRepository repository;
  const MyDraftsPage({super.key, required this.repository});

  @override
  State<MyDraftsPage> createState() => _MyDraftsPageState();
}

class _MyDraftsPageState extends State<MyDraftsPage> {
  late Future<List<ListingDraftRow>> _draftsFuture;

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  void _loadDrafts() {
    _draftsFuture = widget.repository.getAllDrafts();
  }

  Future<void> _publishDraft(ListingDraftRow draft) async {
    final priceController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    // 1. แสดง Dialog ถามราคาสินค้าก่อนเสมอ
    final double? price = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ตั้งราคาสินค้าเพื่อโพสต์ขาย'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'ราคา (บาท)',
                hintText: 'เช่น 150',
                suffixText: 'บาท',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'กรุณากรอกราคา';
                }
                final numValue = double.tryParse(value.trim());
                if (numValue == null || numValue <= 0) {
                  return 'กรุณากรอกราคาเป็นตัวเลขที่มากกว่า 0';
                }
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  final val = double.parse(priceController.text.trim());
                  Navigator.pop(context, val);
                }
              },
              child: const Text('ยืนยันโพสต์'),
            ),
          ],
        );
      },
    );

    if (price == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนโพสต์ขาย')),
      );
      return;
    }

    // แสดง Progress Indicator ระหว่างอัปโหลด
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('กำลังอัปโหลดและโพสต์ขาย...'),
            ],
          ),
        ),
      ),
    );

    try {
      // ตรวจสอบการเชื่อมต่ออินเทอร์เน็ตก่อนโพสต์ (สำหรับขั้นตอนที่ 8.1 ข้อ 3)
      try {
        final result = await InternetAddress.lookup('example.com')
            .timeout(const Duration(seconds: 2));
        if (result.isEmpty || result[0].rawAddress.isEmpty) {
          throw const SocketException('ไม่มีสัญญาณอินเทอร์เน็ต');
        }
      } catch (_) {
        throw Exception('ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบสัญญาณเครือข่าย');
      }

      // 2. อัปโหลดรูปจาก draft.imagePath ขึ้น Storage ก่อน
      String imageUrl = '';
      final file = File(draft.imagePath);
      if (await file.exists()) {
        imageUrl = await StorageService().uploadListingImage(file, user.uid);
      }

      // 3. สร้าง Item จากข้อมูลร่าง + ราคา + sellerId แล้วเขียนลง Firestore
      final item = Item(
        id: DateTime.now().millisecondsSinceEpoch,
        title: draft.title,
        price: price,
        description: draft.description,
        category: draft.category,
        imageUrl: imageUrl,
        sellerId: user.uid,
      );

      await ItemRepositoryFirestore().postItem(item);

      // 4. ลบร่างออกจาก Local Database แล้ว Refresh
      await widget.repository.deleteDraft(draft.id);

      if (mounted) {
        Navigator.pop(context); // ปิด Progress Dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โพสต์ขาย "${draft.title}" สำเร็จแล้ว')),
        );
        setState(() {
          _loadDrafts();
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // ปิด Progress Dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการโพสต์: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ร่างประกาศของฉัน'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรชรายการ',
            onPressed: () {
              setState(() {
                _loadDrafts();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<ListingDraftRow>>(
        future: _draftsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('เกิดข้อผิดพลาด: ${snapshot.error}'));
          }
          final drafts = snapshot.data ?? [];
          if (drafts.isEmpty) {
            return const Center(
              child: Text(
                'ยังไม่มีร่างประกาศที่บันทึกไว้',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            );
          }
          return ListView.builder(
            itemCount: drafts.length,
            itemBuilder: (context, index) {
              final draft = drafts[index];
              final imageFile = File(draft.imagePath);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageFile.existsSync()
                                ? Image.file(
                                    imageFile,
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  )
                                : Container(
                                    width: 60,
                                    height: 60,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.image),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  draft.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  draft.category,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  draft.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            tooltip: 'ลบร่าง',
                            onPressed: () async {
                              await widget.repository.deleteDraft(draft.id);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('ลบร่าง "${draft.title}" แล้ว')),
                                );
                                setState(() {
                                  _loadDrafts();
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: () => _publishDraft(draft),
                          icon:
                              const Icon(Icons.cloud_upload_outlined, size: 18),
                          label: const Text('โพสต์ขายจริง'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
