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

  // --- 1. ฟังก์ชันสร้างโปรเจคใหม่ ---
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
                  'owner_uid': user?.uid, // คนนี้คือเจ้าของสูงสุด
                  'members': [user?.uid],
                  'roles': {user?.uid: 'owner'},
                  'nicknames': {user?.uid: 'ฉัน (เจ้าของ)'},
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

  // --- 2. ฟังก์ชันยืนยันการลบสมาชิก ---
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

  // --- 3. ฟังก์ชันเปลี่ยนตำแหน่ง (Role) ---
  void _showChangeRoleDialog(String docId, String memberUid, String currentRole, String name) {
    String newRole = currentRole;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text("เปลี่ยนตำแหน่ง: $name"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text("ทีมงาน (Worker)"),
                subtitle: const Text("เพิ่มจุดตรวจได้เท่านั้น"),
                value: 'worker',
                groupValue: newRole,
                onChanged: (value) => setStateDialog(() => newRole = value!),
                activeColor: Colors.green,
              ),
              RadioListTile<String>(
                title: const Text("ผู้ช่วยเจ้าของ (Co-Owner)"),
                subtitle: const Text("จัดการสวนได้ (ลบโปรเจคไม่ได้)"),
                value: 'owner',
                groupValue: newRole,
                onChanged: (value) => setStateDialog(() => newRole = value!),
                activeColor: Colors.orange,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                  'roles.$memberUid': newRole,
                });
                if (mounted) {
                   Navigator.pop(context);
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เปลี่ยนตำแหน่งเรียบร้อย")));
                }
              },
              child: const Text("บันทึก"),
            ),
          ],
        ),
      ),
    );
  }

  // --- 4. ฟังก์ชันจัดการสมาชิก ---
  void _manageMembers(String docId) {
    TextEditingController emailController = TextEditingController();
    TextEditingController nicknameController = TextEditingController();
    String selectedRole = 'worker';

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
            Map<String, dynamic> nicknames = gardenData['nicknames'] ?? {};
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
                          // --- ส่วนกรอกข้อมูล ---
                          TextField(
                            controller: emailController,
                            decoration: const InputDecoration(
                              labelText: "อีเมลสมาชิก *",
                              hintText: "example@gmail.com",
                              prefixIcon: Icon(Icons.email_outlined),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                              isDense: true,
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: nicknameController,
                            decoration: const InputDecoration(
                              labelText: "ชื่อเล่น (ไม่บังคับ)",
                              hintText: "เช่น ช่างสมชาย",
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 15),
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
                                subtitle: const Text("จัดการสวนได้ (ลบโปรเจคไม่ได้)"),
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
                                if (emailController.text.isNotEmpty) {
                                  String email = emailController.text.trim();
                                  String nickname = nicknameController.text.trim();
                                  
                                  var userQuery = await FirebaseFirestore.instance
                                      .collection('users').where('email', isEqualTo: email).limit(1).get();

                                  if (userQuery.docs.isEmpty) {
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ไม่พบผู้ใช้นี้")));
                                  } else {
                                    String friendUid = userQuery.docs.first.id;
                                    Map<String, dynamic> updateData = {
                                      'members': FieldValue.arrayUnion([friendUid]),
                                      'roles.$friendUid': selectedRole,
                                    };
                                    if (nickname.isNotEmpty) updateData['nicknames.$friendUid'] = nickname;

                                    await FirebaseFirestore.instance.collection('gardens').doc(docId).update(updateData);
                                    
                                    emailController.clear();
                                    nicknameController.clear();
                                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("เพิ่ม $email แล้ว")));
                                  }
                                }
                              },
                              icon: const Icon(Icons.person_add),
                              label: const Text("เชิญสมาชิก"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                            ),
                          ),
                          
                          const Divider(height: 30, thickness: 1),

                          // --- รายชื่อสมาชิก ---
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
                                    String? nickname = nicknames[memberUid];
                                    bool isMe = (memberUid == user?.uid);
                                    bool isPrimaryOwner = (memberUid == primaryOwnerUid);

                                    return FutureBuilder<DocumentSnapshot>(
                                      future: FirebaseFirestore.instance.collection('users').doc(memberUid).get(),
                                      builder: (context, userSnap) {
                                        String email = "...";
                                        if (userSnap.hasData && userSnap.data!.exists) {
                                          email = userSnap.data!.get('email') ?? "ไม่มีอีเมล";
                                        }

                                        String titleToShow = (nickname != null && nickname.isNotEmpty) ? nickname : email;
                                        
                                        String roleText;
                                        if (isPrimaryOwner) {
                                          roleText = "เจ้าของสูงสุด (Creator)";
                                        } else if (role == 'owner') {
                                          roleText = "ผู้ช่วยเจ้าของ (Co-Owner)";
                                        } else {
                                          roleText = "ทีมงาน (Worker)";
                                        }

                                        String subtitleToShow = (nickname != null && nickname.isNotEmpty) 
                                            ? "$email • $roleText"
                                            : roleText;

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
                                                        onPressed: () => _showChangeRoleDialog(docId, memberUid, role, titleToShow),
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 24),
                                                        onPressed: () => _confirmRemoveMember(docId, memberUid, titleToShow),
                                                      ),
                                                    ],
                                                  ),
                                        );
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

  // --- 5. ฟังก์ชันแก้ไขชื่อโปรเจค ---
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

  // --- 6. ฟังก์ชันลบโปรเจค (สำหรับเจ้าของสูงสุด) ---
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

  // --- [ใหม่!] 7. ฟังก์ชันออกจากโปรเจค (สำหรับ Co-Owner) ---
  void _leaveProject(String docId, String gardenName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("ออกจากโปรเจค"),
        content: Text("คุณต้องการออกจากทีม '$gardenName' ใช่หรือไม่? \n(คุณจะไม่เห็นสวนนี้อีกจนกว่าจะได้รับเชิญใหม่)"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("ยกเลิก")),
          TextButton(
            onPressed: () async {
              // ลบตัวเองออกจากสมาชิก
              await FirebaseFirestore.instance.collection('gardens').doc(docId).update({
                'members': FieldValue.arrayRemove([user!.uid]),
                'roles.${user!.uid}': FieldValue.delete(),
                'nicknames.${user!.uid}': FieldValue.delete(),
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
              
              // --- Logic การเช็ค Role ---
              String primaryOwnerUid = data['owner_uid'] ?? "";
              Map<String, dynamic> roles = data['roles'] ?? {};
              String myRole = roles[user?.uid] ?? 'worker';
              
              bool isPrimaryOwner = (user?.uid == primaryOwnerUid); // เจ้าของสูงสุด
              bool isCoOwner = (!isPrimaryOwner && myRole == 'owner'); // ผู้ช่วยเจ้าของ (Co-Owner)

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isPrimaryOwner ? Colors.green : Colors.orange, // เจ้าของสีเขียว, Co-owner สีส้ม
                    child: const Icon(Icons.eco, color: Colors.white),
                  ),
                  title: Text(gardenName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    isPrimaryOwner ? "สถานะ: เจ้าของสูงสุด" 
                    : (isCoOwner ? "สถานะ: ผู้ช่วยเจ้าของ" : "สถานะ: ทีมงาน")
                  ), 
                  
                  // แสดงปุ่มถ้าเป็น Primary หรือ Co-Owner
                  trailing: (isPrimaryOwner || isCoOwner) ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ปุ่มจัดการสมาชิก
                      IconButton(
                        icon: const Icon(Icons.people, color: Colors.blue),
                        tooltip: "จัดการสมาชิก",
                        onPressed: () => _manageMembers(docId),
                      ),
                      // ปุ่มแก้ไขชื่อ
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.orange),
                        tooltip: "แก้ไขชื่อ",
                        onPressed: () => _editProject(docId, gardenName),
                      ),
                      
                      // --- ปุ่มลบ (ทำงานต่างกันตาม Role) ---
                      if (isPrimaryOwner) 
                        // เจ้าของสูงสุด: ลบโปรเจค
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: "ลบโปรเจคถาวร",
                          onPressed: () => _deleteProject(docId),
                        )
                      else if (isCoOwner)
                        // Co-Owner: ออกจากโปรเจค (ใช้ไอคอน exit_to_app ให้สื่อความหมาย แต่ถ้าชอบถังขยะก็ใช้ delete ได้)
                        IconButton(
                          icon: const Icon(Icons.exit_to_app, color: Colors.redAccent), // เปลี่ยนไอคอนให้สื่อความหมาย
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