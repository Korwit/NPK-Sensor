import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'inspection_dates_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  User? get user => FirebaseAuth.instance.currentUser;

  // --- 1. ฟังก์ชันสร้างโปรเจคใหม่ (ตัด nicknames ออก) ---
  void _createNewProject() {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("สร้างโปรเจคใหม่"),
        content: TextField(
          controller: nameController,
          maxLength: 20,
          decoration: const InputDecoration(hintText: "ชื่อสวน"),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                FirebaseFirestore.instance.collection('gardens').add({
                  'name': nameController.text,
                  'owner_uid': user?.uid,
                  'members': [user?.uid],
                  'roles': {user?.uid: 'owner'},
                  // 'nicknames': ... ตัดออกแล้ว! ไม่เก็บในสวนแล้ว
                  'created_at': FieldValue.serverTimestamp(),
                });
                Navigator.pop(context);
              }
            },
            child: const Text("สร้าง"),
          ),
        ],
      ),
    );
  }

  // --- 2. ฟังก์ชันจัดการสมุดรายชื่อ (หัวใจหลักของการเก็บชื่อ) ---
  Future<void> _updateContactInfo(String friendUid, String email, String? nickname) async {
    // ถ้าชื่อเล่นว่างเปล่า -> ไม่บันทึกชื่อ แต่บันทึก email ไว้
    // หรือถ้าอยากให้ลบชื่อเก่าออก ก็ส่ง "" มา
    await FirebaseFirestore.instance
        .collection('users').doc(user!.uid)
        .collection('contacts').doc(friendUid)
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
                .collection('users').doc(user!.uid)
                .collection('contacts')
                .orderBy('nickname')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text("เกิดข้อผิดพลาด"));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              var docs = snapshot.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Text("ยังไม่มีรายชื่อ"));
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
                    title: Text(nickname.isNotEmpty ? nickname : email, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: nickname.isNotEmpty ? Text(email) : null,
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      onPressed: () {
                        FirebaseFirestore.instance
                            .collection('users').doc(user!.uid)
                            .collection('contacts').doc(uid)
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

  // --- 3. ฟังก์ชันยืนยันการลบสมาชิก ---
  void _confirmRemoveMember(String docId, String memberUid, String nameToShow) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ยืนยันการลบ"),
        content: Text("คุณต้องการลบ '$nameToShow' ออกจากสวนนี้ใช่หรือไม่?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                'members': FieldValue.arrayRemove([memberUid]),
                'roles.$memberUid': FieldValue.delete(),
                // ไม่ต้องลบ nicknames ในสวนแล้ว เพราะไม่มีแล้ว
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

  // --- 4. ฟังก์ชันจัดการ: เปลี่ยน Role (สวน) + เปลี่ยนชื่อ (Contact ส่วนตัว) ---
  void _editMemberInfo(String docId, String memberUid, String currentRole, String? currentNickname, String email) {
    String newRole = currentRole;
    TextEditingController nicknameController = TextEditingController(text: currentNickname ?? "");

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text("จัดการสมาชิก"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("ชื่อเล่น (ส่วนตัว)", style: TextStyle(fontWeight: FontWeight.bold)),
                TextField(
                  controller: nicknameController,
                  decoration: const InputDecoration(
                    hintText: "ชื่อที่คุณเรียกคนนี้",
                    isDense: true,
                    prefixIcon: Icon(Icons.edit, size: 18),
                    helperText: "บันทึกลงสมุดรายชื่อส่วนตัวของคุณ",
                    helperStyle: TextStyle(color: Colors.blue),
                  ),
                ),
                const SizedBox(height: 20),

                const Text("ตำแหน่งในสวนนี้", style: TextStyle(fontWeight: FontWeight.bold)),
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
                // 1. อัปเดต Role ใน Garden (Shared)
                await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                  'roles.$memberUid': newRole,
                });
                
                // 2. อัปเดต Nickname ใน Contacts (Private)
                String newName = nicknameController.text.trim();
                await _updateContactInfo(memberUid, email, newName); // บันทึกเสมอไม่ว่าจะว่างหรือไม่

                if (mounted) {
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("บันทึกข้อมูลเรียบร้อย")));
                }
              },
              child: const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );
  }

  // --- 5. ฟังก์ชันจัดการสมาชิก (Main) ---
  void _manageMembers(String docId) {
    String currentInputEmail = ""; 
    TextEditingController emailTextController = TextEditingController(); 
    TextEditingController nicknameController = TextEditingController();
    String selectedRole = 'worker';
    bool saveToContacts = true; // ตั้ง Default เป็น true เลยก็ได้เพื่อความสะดวก

    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('gardens').doc(docId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

            var gardenData = snapshot.data!.data() as Map<String, dynamic>;
            List<dynamic> members = gardenData['members'] ?? [];
            Map<String, dynamic> roles = gardenData['roles'] ?? {};
            String primaryOwnerUid = gardenData['owner_uid'] ?? ""; 

            return AlertDialog(
              title: const Text("จัดการสมาชิก"),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: StatefulBuilder(
                    builder: (context, setStateDialog) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- Search & Add ---
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Autocomplete<String>(
                                  optionsBuilder: (TextEditingValue textEditingValue) async {
                                    if (textEditingValue.text.length < 3) return const Iterable<String>.empty();
                                    // ค้นหาจาก Contact เราก่อน (จะได้เจอชื่อเล่น) หรือ Users ทั้งหมดก็ได้
                                    // ในที่นี้ค้นจาก Users ทั้งหมดเพื่อให้เจอคนใหม่ๆ
                                    var querySnapshot = await FirebaseFirestore.instance
                                        .collection('users')
                                        .where('email', isGreaterThanOrEqualTo: textEditingValue.text)
                                        .where('email', isLessThan: '${textEditingValue.text}z')
                                        .limit(5).get();
                                    return querySnapshot.docs.map((doc) => doc['email'] as String);
                                  },
                                  onSelected: (String selection) {
                                    currentInputEmail = selection;
                                    emailTextController.text = selection;
                                  },
                                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                                    if (emailTextController.text != controller.text) controller.text = emailTextController.text;
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
                                  _showContactsBook((email, nickname) {
                                    setStateDialog(() {
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
                              labelText: "ชื่อเล่น (ส่วนตัว)",
                              hintText: "เช่น ช่างสมชาย",
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
                              setStateDialog(() {
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
                                onChanged: (value) => setStateDialog(() => selectedRole = value!),
                              ),
                              RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: const Text("ผู้ช่วยเจ้าของ (Co-Owner)"),
                                subtitle: const Text("จัดการสวนได้ (แต่ลบโปรเจคไม่ได้)"),
                                value: 'owner',
                                groupValue: selectedRole,
                                activeColor: Colors.orange,
                                onChanged: (value) => setStateDialog(() => selectedRole = value!),
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
                                  
                                  var userQuery = await FirebaseFirestore.instance
                                      .collection('users').where('email', isEqualTo: email).limit(1).get();

                                  if (userQuery.docs.isEmpty) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ไม่พบผู้ใช้นี้")));
                                  } else {
                                    String friendUid = userQuery.docs.first.id;
                                    
                                    if (members.contains(friendUid)) {
                                       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("สมาชิกคนนี้มีอยู่แล้ว")));
                                       return;
                                    }

                                    // 1. เพิ่มเข้า Garden (Shared) - *ไม่มี nickname แล้ว*
                                    await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                                      'members': FieldValue.arrayUnion([friendUid]),
                                      'roles.$friendUid': selectedRole,
                                    });
                                    
                                    // 2. บันทึกลง Contacts (Private) - *เก็บ nickname ที่นี่*
                                    if (saveToContacts || nickname.isNotEmpty) {
                                      await _updateContactInfo(friendUid, email, nickname);
                                    }

                                    emailTextController.clear();
                                    currentInputEmail = "";
                                    nicknameController.clear();

                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("เพิ่ม $email เรียบร้อย")));
                                  }
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("กรุณาระบุอีเมล")));
                                }
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text("เชิญสมาชิก"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                            ),
                          ),
                          
                          const Divider(height: 30, thickness: 1),

                          // --- รายชื่อสมาชิก (ส่วนแสดงผล) ---
                          ExpansionTile(
                            title: Text("รายชื่อสมาชิก (${members.length})", 
                              style: TextStyle(color: Colors.grey[800], fontWeight: FontWeight.bold)
                            ),
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
                                    bool isMe = (memberUid == user?.uid);
                                    bool isPrimaryOwner = (memberUid == primaryOwnerUid);

                                    // ตรงนี้สำคัญ! ต้องดึงข้อมูลจาก Contacts ของเรามาแสดง (ไม่ใช่จาก Garden)
                                    return StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance
                                          .collection('users').doc(user!.uid)
                                          .collection('contacts').doc(memberUid)
                                          .snapshots(), // ฟัง Contact เราก่อน
                                      builder: (context, contactSnap) {
                                        
                                        // ถ้ามีใน Contact -> ใช้ชื่อจาก Contact
                                        // ถ้าไม่มี -> ไปดึง Email จาก Users กลาง
                                        
                                        if (contactSnap.hasData && contactSnap.data!.exists) {
                                          // มี Contact: ใช้ข้อมูลส่วนตัวเรา
                                          var cData = contactSnap.data!.data() as Map<String, dynamic>;
                                          String nickname = cData['nickname'] ?? "";
                                          String email = cData['email'] ?? "...";
                                          return _buildMemberTile(docId, memberUid, role, email, nickname, isMe, isPrimaryOwner);
                                        } else {
                                          // ไม่มี Contact: ไปดึง User กลาง
                                          return FutureBuilder<DocumentSnapshot>(
                                            future: FirebaseFirestore.instance.collection('users').doc(memberUid).get(),
                                            builder: (context, userSnap) {
                                              String email = "...";
                                              if (userSnap.hasData && userSnap.data!.exists) {
                                                email = userSnap.data!.get('email') ?? "ไม่มีอีเมล";
                                              }
                                              return _buildMemberTile(docId, memberUid, role, email, "", isMe, isPrimaryOwner);
                                            },
                                          );
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("ปิด")),
              ],
            );
          },
        );
      },
    );
  }

  // --- Helper Widget สำหรับสร้าง ListTile สมาชิก (จะได้ไม่เขียนซ้ำ) ---
  Widget _buildMemberTile(String docId, String memberUid, String role, String email, String nickname, bool isMe, bool isPrimaryOwner) {
    String titleToShow = (nickname.isNotEmpty) ? nickname : email;
    String roleText;
    
    if (isPrimaryOwner) roleText = "เจ้าของสูงสุด";
    else if (role == 'owner') roleText = "ผู้ช่วย";
    else roleText = "ทีมงาน";

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
            color: isPrimaryOwner ? Colors.amber[900] : (role == 'owner' ? Colors.orange[800] : Colors.green[800]),
            fontWeight: FontWeight.bold
          ),
        ),
      ),
      title: Text(titleToShow, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitleToShow, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      trailing: isMe 
        ? const Text("(คุณ)", style: TextStyle(color: Colors.grey, fontSize: 12))
        : isPrimaryOwner 
            ? const Text("เจ้าของ", style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.manage_accounts, color: Colors.blue, size: 24),
                    // กดแล้วแก้ทั้ง Role และชื่อ (เข้า Contact)
                    onPressed: () => _editMemberInfo(docId, memberUid, role, nickname, email),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 24),
                    onPressed: () => _confirmRemoveMember(docId, memberUid, titleToShow),
                  ),
                ],
              ),
    );
  }

  // --- 6. ฟังก์ชันแก้ไขชื่อโปรเจค ---
  void _editProject(String docId, String currentName) {
    TextEditingController nameController = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("เปลี่ยนชื่อโปรเจค"),
        content: TextField(
          controller: nameController,
          maxLength: 20,
          decoration: const InputDecoration(hintText: "ชื่อสวนใหม่"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                FirebaseFirestore.instance.collection('gardens').doc(docId).update({'name': nameController.text});
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เปลี่ยนชื่อเรียบร้อย!")));
              }
            },
            child: const Text("บันทึก"),
          ),
        ],
      ),
    );
  }

  // --- 7. ฟังก์ชันลบโปรเจค ---
  void _deleteProject(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ลบโปรเจคถาวร"),
        content: const Text("คุณแน่ใจไหม? ข้อมูลทั้งหมดจะหายไปและกู้คืนไม่ได้"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('gardens').doc(docId).delete();
              Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ลบถาวร"),
          ),
        ],
      ),
    );
  }

  // --- 8. ฟังก์ชันออกจากโปรเจค ---
  void _leaveProject(String docId, String gardenName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ออกจากโปรเจค"),
        content: Text("คุณต้องการออกจากทีม '$gardenName' ใช่หรือไม่?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                'members': FieldValue.arrayRemove([user!.uid]),
                'roles.${user!.uid}': FieldValue.delete(),
                // ไม่ต้องลบ nicknames เพราะไม่มีแล้ว
              });
              if (mounted) Navigator.pop(context);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("ออก"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("เลือกโปรเจคสวน"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance
            .collection('gardens')
            .where('members', arrayContains: user?.uid)
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}")); 
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var docs = snapshot.data!.docs;
          if (docs.isEmpty) return const Center(child: Text("ไม่พบโปรเจค กด + เพื่อสร้างใหม่"));

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data();
              String docId = docs[index].id;
              String gardenName = data['name'] ?? "ไม่มีชื่อ";
              
              String primaryOwnerUid = data['owner_uid'] ?? "";
              Map<String, dynamic> roles = data['roles'] ?? {};
              String myRole = roles[user?.uid] ?? 'worker';
              
              bool isPrimaryOwner = (user?.uid == primaryOwnerUid);
              bool isCoOwner = (!isPrimaryOwner && myRole == 'owner');

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPrimaryOwner ? Colors.green : Colors.orange,
                    child: const Icon(Icons.eco, color: Colors.white),
                  ),
                  title: Text(gardenName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    isPrimaryOwner ? "สถานะ: เจ้าของสูงสุด" 
                    : (isCoOwner ? "สถานะ: ผู้ช่วยเจ้าของ" : "สถานะ: ทีมงาน")
                  ), 
                  
                  trailing: (isPrimaryOwner || isCoOwner) ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.people, color: Colors.blue),
                        tooltip: "จัดการสมาชิก",
                        onPressed: () => _manageMembers(docId),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        tooltip: "แก้ไขชื่อ",
                        onPressed: () => _editProject(docId, gardenName),
                      ),
                      if (isPrimaryOwner) 
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "ลบโปรเจคถาวร",
                          onPressed: () => _deleteProject(docId),
                        )
                      else if (isCoOwner)
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                          tooltip: "ออกจากโปรเจค",
                          onPressed: () => _leaveProject(docId, gardenName),
                        ),
                    ],
                  ) : null, 
                  
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => InspectionDatesPage(
                          gardenId: docId, 
                          gardenName: gardenName,
                          userRole: myRole,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewProject,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add),
      ),
    );
  }
}