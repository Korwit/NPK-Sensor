#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- ตั้งค่า UUID (ต้องตรงกับในไฟล์ Flutter ble_service.dart เป๊ะๆ) ---
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// ตัวแปรเก็บค่า NPK และความชื้น
int n_val = 0;
int p_val = 0;
int k_val = 0;
int moist_val = 0;

// --- Callback ตรวจจับการเชื่อมต่อ ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("App Connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("App Disconnected!");
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting BLE work!");

  // 1. เริ่มต้น BLE
  BLEDevice::init("NPK Sensor"); // ชื่อที่จะโชว์ในแอปตอนสแกน

  // 2. สร้าง Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // 3. สร้าง Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // 4. สร้าง Characteristic
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // เพิ่ม Descriptor (จำเป็นสำหรับการแจ้งเตือน)
  pCharacteristic->addDescriptor(new BLE2902());

  // 5. เริ่ม Service
  pService->start();

  // 6. เริ่มโฆษณา (Advertising) ให้แอปหาเจอ
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);
  BLEDevice::startAdvertising();
  Serial.println("Waiting for connection...");
}

void loop() {
  // --- ส่วนอ่านค่า Sensor ---
  // ถ้าคุณมีเซนเซอร์จริง ให้เรียกฟังก์ชันอ่าน RS485 ตรงนี้
  // readRealSensor(); 
  
  // *** สำหรับทดสอบ: สุ่มเลขจำลองค่า ***
  n_val = random(10, 100);
  p_val = random(10, 100);
  k_val = random(10, 100);
  moist_val = random(40, 90);

  // --- ส่วนส่งข้อมูลผ่าน BLE ---
  if (deviceConnected) {
    // เตรียมข้อมูลส่งเป็น Byte Array (4 ช่อง: N, P, K, Moisture)
    uint8_t data[4];
    data[0] = (uint8_t)n_val;
    data[1] = (uint8_t)p_val;
    data[2] = (uint8_t)k_val;
    data[3] = (uint8_t)moist_val;

    // อัปเดตค่าลงใน Characteristic
    pCharacteristic->setValue(data, 4);
    
    // แจ้งเตือนไปยังแอป (ถ้าแอป Subscribe ไว้ แต่ในเคสนี้แอปเรากด Read เองก็ค่าเปลี่ยนเหมือนกัน)
    pCharacteristic->notify();

    Serial.printf("Sent: N=%d, P=%d, K=%d, Moist=%d\n", n_val, p_val, k_val, moist_val);
    delay(2000); // อัปเดตทุก 2 วินาที
  }

  // จัดการเรื่องการเชื่อมต่อหลุดแล้วต่อใหม่
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); 
    pServer->startAdvertising(); // เริ่มโฆษณาใหม่เมื่อหลุด
    Serial.println("Start advertising...");
    oldDeviceConnected = deviceConnected;
  }
  
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }
}

// ---------------------------------------------------------
// ตัวอย่างฟังก์ชันอ่านค่าจริง (ถ้าใช้ RS485 Modbus)
// ต้องต่อขา: DI->TX2(17), RO->RX2(16), DE/RE->GPIO 4
// ---------------------------------------------------------
/*
#define RE_DE_PIN 4 
const byte code[] = {0x01, 0x03, 0x00, 0x1E, 0x00, 0x03, 0x65, 0xCD}; // ตัวอย่าง Command NPK (แล้วแต่รุ่น)
byte values[11];

void readRealSensor() {
  pinMode(RE_DE_PIN, OUTPUT);
  Serial2.begin(4800, SERIAL_8N1, 16, 17); // RX=16, TX=17

  // ส่งคำสั่งขอข้อมูล
  digitalWrite(RE_DE_PIN, HIGH);
  Serial2.write(code, sizeof(code));
  Serial2.flush();
  digitalWrite(RE_DE_PIN, LOW);
  delay(200);

  // อ่านค่ากลับ
  if (Serial2.available() >= 11) {
    for (int i = 0; i < 11; i++) {
      values[i] = Serial2.read();
    }
    // แปลงค่า (ขึ้นอยู่กับ Datasheet ของเซนเซอร์แต่ละรุ่น)
    n_val = values[3] * 256 + values[4];
    p_val = values[5] * 256 + values[6];
    k_val = values[7] * 256 + values[8];
    // ถ้ามี Moisture ก็อ่านต่อ
  }
}
*/