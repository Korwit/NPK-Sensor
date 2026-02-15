import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MemberManagementDialog extends StatefulWidget {
  final String docId; // ID ของสวน (Garden Document ID)
  final User currentUser; // User ปัจจุบันที่ล็อกอินอยู่

  const MemberManagementDialog({
    super.key,
    required this.docId,
    required this.currentUser,
  });

  @override
  State<MemberManagementDialog> createState() => _MemberManagementDialogState();
}

class _MemberManagementDialogState extends State<MemberManagementDialog> {
  String currentInputEmail = "";
  TextEditingController emailTextController = TextEditingController();
  TextEditingController nicknameController = TextEditingController();
  String selectedRole = 'worker'; // Default role
  bool saveToContacts = true; // Default checkbox

  // --- 1. ฟังก์ชันจัดการสมุดรายชื่อ (Private Contacts) ---
  Future<void> _updateContactInfo(String friendUid, String email, String? nickname) async {
    // เก็บรายชื่อเพื่อนไว้ใน users -> contacts ของเราเอง เพื่อเรียกใช้ง่ายๆ ครั้งหน้า
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUser.uid)
        .collection('contacts')
        .doc(friendUid)
        .set({
      'uid': friendUid,
      'email': email,
      'nickname': nickname ?? "",
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _showContactsBook(Function(String email, String nickname) onSelected) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("สมุดรายชื่อส่วนตัว"),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.currentUser.uid)
                .collection('contacts')
                .orderBy('nickname')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text("เกิดข้อผิดพลาด"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              var docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text("ยังไม่มีรายชื่อที่บันทึกไว้"));
              }

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  String email = data['email'] ?? "";
                  String nickname = data['nickname'] ?? "";
                  String uid = docs[index].id;

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      child: Text(
                        (nickname.isNotEmpty ? nickname : email).substring(0, 1).toUpperCase(),
                        style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(nickname.isNotEmpty ? nickname : email,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: nickname.isNotEmpty ? Text(email) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () {
                        // ลบออกจากสมุดรายชื่อส่วนตัว
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(widget.currentUser.uid)
                            .collection('contacts')
                            .doc(uid)
                            .delete();
                      },
                    ),
                    onTap: () {
                      onSelected(email, nickname);
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ปิด")),
        ],
      ),
    );
  }

  // --- 2. ฟังก์ชันยืนยันการลบสมาชิกออกจากสวน ---
  void _confirmRemoveMember(String memberUid, String nameToShow) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: Text("คุณต้องการลบ '$nameToShow' ออกจากสวนนี้ใช่หรือไม่?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              // ลบ uid ออกจาก array และลบ field ใน map
              await FirebaseFirestore.instance.collection('gardens').doc(widget.docId).update({
                'members': FieldValue.arrayRemove([memberUid]),
                'roles.$memberUid': FieldValue.delete(),
                'nicknames.$memberUid': FieldValue.delete(),
              });
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบออก"),
          ),
        ],
      ),
    );
  }

  // --- 3. ฟังก์ชันแก้ไข Role และชื่อเล่น ---
  void _editMemberInfo(
      String memberUid, String currentRole, String? currentNickname, String email) {
    String newRole = currentRole;
    TextEditingController nicknameEditor = TextEditingController(text: currentNickname ?? "");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text("จัดการสมาชิก"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ชื่อเล่นในโปรเจค", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: nicknameEditor,
                  decoration: const InputDecoration(
                    hintText: "เช่น ช่างสมชาย",
                    isDense: true,
                    prefixIcon: Icon(Icons.edit, size: 18),
                    helperText: "จะอัปเดตในสมุดรายชื่อของคุณด้วย",
                    helperStyle: TextStyle(color: Colors.blue),
                  ),
                ),
                const SizedBox(height: 20),
                const Text("ตำแหน่ง", style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<String>(
                  title: const Text("ทีมงาน (Worker)"),
                  subtitle: const Text("เพิ่มจุดตรวจได้เท่านั้น"),
                  value: 'worker',
                  groupValue: newRole,
                  onChanged: (value) => setStateDialog(() => newRole = value!),
                  activeColor: Colors.green,
                  contentPadding: EdgeInsets.zero,
                ),
                RadioListTile<String>(
                  title: const Text("ผู้ช่วยเจ้าของ (Co-Owner)"),
                  subtitle: const Text("จัดการสวนได้ (แต่ลบโปรเจคไม่ได้)"),
                  value: 'owner',
                  groupValue: newRole,
                  onChanged: (value) => setStateDialog(() => newRole = value!),
                  activeColor: Colors.orange,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
            ElevatedButton(
              onPressed: () async {
                // 1. เตรียมข้อมูลอัปเดตใน Garden
                Map<String, dynamic> updates = {
                  'roles.$memberUid': newRole,
                };
                String newNickname = nicknameEditor.text.trim();
                if (newNickname.isNotEmpty) {
                  updates['nicknames.$memberUid'] = newNickname;
                } else {
                  updates['nicknames.$memberUid'] = FieldValue.delete();
                }

                await FirebaseFirestore.instance
                    .collection('gardens')
                    .doc(widget.docId)
                    .update(updates);

                // 2. ซิงค์ไปที่ Contacts ด้วย
                if (newNickname.isNotEmpty) {
                  await _updateContactInfo(memberUid, email, newNickname);
                }

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("บันทึกข้อมูลเรียบร้อย")));
                }
              },
              child: const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );
  }

  // --- Widget ย่อย: แสดงรายการสมาชิกแต่ละคน ---
  Widget _buildMemberTile(String memberUid, String role, String email, String nickname, bool isMe,
      bool isPrimaryOwner) {
    String titleToShow = (nickname.isNotEmpty) ? nickname : email;
    String roleText;

    if (isPrimaryOwner) {
      roleText = "เจ้าของสูงสุด";
    } else if (role == 'owner') {
      roleText = "ผู้ช่วย";
    } else {
      roleText = "ทีมงาน";
    }

    String subtitleToShow = (nickname.isNotEmpty) ? "$email • $roleText" : roleText;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: isPrimaryOwner
            ? Colors.amber[100]
            : (role == 'owner' ? Colors.orange[100] : Colors.green[100]),
        child: Text(
          titleToShow.substring(0, 1).toUpperCase(),
          style: TextStyle(
              color: isPrimaryOwner
                  ? Colors.amber[900]
                  : (role == 'owner' ? Colors.orange[800] : Colors.green[800]),
              fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(titleToShow, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitleToShow, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      trailing: isMe
          ? const Text("(คุณ)", style: TextStyle(color: Colors.grey, fontSize: 12))
          : isPrimaryOwner
              ? const Text("เจ้าของ",
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.manage_accounts, color: Colors.blue, size: 24),
                      onPressed: () => _editMemberInfo(memberUid, role, nickname, email),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 24),
                      onPressed: () => _confirmRemoveMember(memberUid, titleToShow),
                    ),
                  ],
                ),
    );
  }

  // --- Main Build ---
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      // ดึงข้อมูล Real-time ของสวนนี้
      stream: FirebaseFirestore.instance.collection('gardens').doc(widget.docId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        var gardenData = snapshot.data!.data() as Map<String, dynamic>;
        List<dynamic> members = gardenData['members'] ?? [];
        Map<String, dynamic> roles = gardenData['roles'] ?? {};
        Map<String, dynamic> nicknames = gardenData['nicknames'] ?? {};
        String primaryOwnerUid = gardenData['owner_uid'] ?? "";

        return AlertDialog(
          title: const Text("จัดการสมาชิก"),
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- ส่วนที่ 1: ค้นหาและเชิญสมาชิก ---
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        // ช่องค้นหาอีเมลแบบ Autocomplete
                        child: Autocomplete<String>(
                          optionsBuilder: (TextEditingValue textEditingValue) async {
                            if (textEditingValue.text.length < 3) {
                              return const Iterable<String>.empty();
                            }
                            // ค้นหา Users จาก Collection 'users' (ที่บันทึกตอน Login)
                            var querySnapshot = await FirebaseFirestore.instance
                                .collection('users')
                                .where('email', isGreaterThanOrEqualTo: textEditingValue.text)
                                .where('email', isLessThan: '${textEditingValue.text}z')
                                .limit(5)
                                .get();
                            return querySnapshot.docs.map((doc) => doc['email'] as String);
                          },
                          onSelected: (String selection) {
                            currentInputEmail = selection;
                            emailTextController.text = selection;
                          },
                          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                            if (emailTextController.text != controller.text) {
                              controller.text = emailTextController.text;
                            }
                            controller.addListener(() {
                              currentInputEmail = controller.text;
                              emailTextController.text = controller.text;
                            });
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              decoration: const InputDecoration(
                                labelText: "อีเมลสมาชิก *",
                                hintText: "ค้นหา...",
                                prefixIcon: Icon(Icons.search),
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                                isDense: true,
                              ),
                              keyboardType: TextInputType.emailAddress,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      IconButton.filledTonal(
                        onPressed: () {
                          // เปิดสมุดรายชื่อ
                          _showContactsBook((email, nickname) {
                            setState(() {
                              emailTextController.text = email;
                              currentInputEmail = email;
                              if (nickname.isNotEmpty) nicknameController.text = nickname;
                            });
                          });
                        },
                        icon: const Icon(Icons.contacts),
                        tooltip: "เลือกจากสมุดรายชื่อ",
                      )
                    ],
                  ),

                  const SizedBox(height: 10),
                  TextField(
                    controller: nicknameController,
                    decoration: const InputDecoration(
                      labelText: "ชื่อเล่นในโปรเจคนี้",
                      hintText: "เช่น คนงานเอ",
                      prefixIcon: Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                      isDense: true,
                    ),
                  ),

                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("บันทึกลงสมุดรายชื่อส่วนตัว", style: TextStyle(fontSize: 14)),
                    value: saveToContacts,
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (bool? value) {
                      setState(() {
                        saveToContacts = value ?? true;
                      });
                    },
                  ),

                  const Text("เลือกสิทธิ์การใช้งาน:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("ทีมงาน (Worker)"),
                        subtitle: const Text("เพิ่มจุดตรวจได้เท่านั้น"),
                        value: 'worker',
                        groupValue: selectedRole,
                        activeColor: Colors.green,
                        onChanged: (value) => setState(() => selectedRole = value!),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("ผู้ช่วยเจ้าของ (Co-Owner)"),
                        subtitle: const Text("จัดการสวนได้ (แต่ลบโปรเจคไม่ได้)"),
                        value: 'owner',
                        groupValue: selectedRole,
                        activeColor: Colors.orange,
                        onChanged: (value) => setState(() => selectedRole = value!),
                      ),
                    ],
                  ),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        if (currentInputEmail.isNotEmpty) {
                          String email = currentInputEmail.trim();
                          String nickname = nicknameController.text.trim();

                          // 1. หา UID จาก Email ใน Users Collection
                          var userQuery = await FirebaseFirestore.instance
                              .collection('users')
                              .where('email', isEqualTo: email)
                              .limit(1)
                              .get();

                          if (userQuery.docs.isEmpty) {
                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(const SnackBar(content: Text("ไม่พบผู้ใช้นี้ (ต้องให้เขาล็อกอินเข้าระบบก่อน 1 ครั้ง)")));
                            }
                          } else {
                            String friendUid = userQuery.docs.first.id;

                            if (members.contains(friendUid)) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("สมาชิกคนนี้มีอยู่แล้ว")));
                              }
                              return;
                            }

                            // 2. เพิ่มเข้า Garden
                            Map<String, dynamic> updateData = {
                              'members': FieldValue.arrayUnion([friendUid]),
                              'roles.$friendUid': selectedRole,
                            };
                            if (nickname.isNotEmpty) {
                              updateData['nicknames.$friendUid'] = nickname;
                            }

                            await FirebaseFirestore.instance
                                .collection('gardens')
                                .doc(widget.docId)
                                .update(updateData);

                            // 3. บันทึกลง Contacts (ถ้าติ๊กเลือก)
                            if (saveToContacts || nickname.isNotEmpty) {
                              await _updateContactInfo(friendUid, email, nickname);
                            }

                            // เคลียร์ค่า
                            emailTextController.clear();
                            currentInputEmail = "";
                            nicknameController.clear();

                            if (mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(content: Text("เพิ่ม $email เรียบร้อย")));
                            }
                          }
                        } else {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text("กรุณาระบุอีเมล")));
                        }
                      },
                      icon: const Icon(Icons.person_add),
                      label: const Text("เชิญสมาชิก"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue, foregroundColor: Colors.white),
                    ),
                  ),

                  const Divider(height: 30, thickness: 1),

                  // --- ส่วนที่ 2: แสดงรายชื่อสมาชิก ---
                  ExpansionTile(
                    title: Text("รายชื่อสมาชิก (${members.length})",
                        style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold)),
                    initiallyExpanded: false,
                    tilePadding: EdgeInsets.zero,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            String memberUid = members[index];
                            String role = roles[memberUid] ?? 'worker';
                            String? nickname = nicknames[memberUid];
                            bool isMe = (memberUid == widget.currentUser.uid);
                            bool isPrimaryOwner = (memberUid == primaryOwnerUid);

                            // ดึง Email มาแสดง (ถ้าไม่มี nickname)
                            return FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(memberUid)
                                  .get(),
                              builder: (context, userSnap) {
                                String email = "...";
                                if (userSnap.hasData && userSnap.data!.exists) {
                                  email = userSnap.data!.get('email') ?? "ไม่มีอีเมล";
                                }

                                return _buildMemberTile(
                                    memberUid, role, email, nickname ?? "", isMe, isPrimaryOwner);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ปิด")),
          ],
        );
      },
    );
  }
}