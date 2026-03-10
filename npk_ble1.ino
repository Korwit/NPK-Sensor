#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ==========================================
// BLE UUID (ต้องตรงกับ Flutter)
// ==========================================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// ==========================================
// PIN
// ==========================================
#define RE            4
#define RXD2          17
#define TXD2          16
#define ANALOG_IN_PIN 36
#define SLEEP_BTN_PIN 14   // ปุ่ม deep sleep
#define SEND_BTN_PIN  33   // ปุ่มกดส่งค่า NPK ผ่าน BLE
#define Relay         13
#define SDA           21
#define SCL           22

#define REF_VOLTAGE    3.295
#define ADC_RESOLUTION 4096.0
#define R1             30000.0
#define R2             7500.0

// ==========================================
// ตัวแปร global
// ==========================================
const unsigned long interval = 5000;
unsigned long previousMillis = 0, relayMillis = 0;

const byte read_all[] = { 0x01, 0x03, 0x00, 0x00, 0x00, 0x08, 0x44, 0x0C };
byte values[25];

// ค่าล่าสุดจากเซนเซอร์ — อัปเดตทุก 5 วิ รอให้กดปุ่มค่อยส่ง
uint8_t lastN = 0, lastP = 0, lastK = 0, lastMoist = 0;
bool hasValidData = false;

volatile bool sleepBtnPressed = false;

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

LiquidCrystal_I2C lcd(0x27, 20, 4);

// ==========================================
// BLE Callbacks
// ==========================================
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 โทรศัพท์เชื่อมต่อแล้ว!");
  }
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("❌ โทรศัพท์ตัดการเชื่อมต่อ...");
    BLEDevice::startAdvertising();
  }
};

// ==========================================
// Interrupt — ปุ่ม deep sleep เท่านั้น
// ปุ่มส่งค่า (ขา 33) ใช้ polling เพื่อความเสถียร
// ==========================================
void IRAM_ATTR handleSleepBtn() {
  sleepBtnPressed = true;
}

// ==========================================
// Setup
// ==========================================
void setup() {
  Serial.begin(9600);
  gpio_hold_dis(GPIO_NUM_13);
  gpio_deep_sleep_hold_dis();

  // LCD
  Wire.begin(SDA, SCL);
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("Soil Monitor");
  delay(2000);
  lcd.clear();

  // ปุ่ม deep sleep (ขา 14)
  pinMode(SLEEP_BTN_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(SLEEP_BTN_PIN), handleSleepBtn, FALLING);

  // ปุ่มส่งค่า NPK (ขา 33) — polling
  pinMode(SEND_BTN_PIN, INPUT_PULLUP);

  // RS485
  Serial1.begin(9600, SERIAL_8N1, RXD2, TXD2);
  pinMode(RE, OUTPUT);
  digitalWrite(RE, LOW);

  // Relay
  pinMode(Relay, OUTPUT);
  digitalWrite(Relay, LOW);

  // BLE
  BLEDevice::init("NPK_Sensor");
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);
  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  // จำเป็นต้องมีเพื่อให้ Flutter setNotifyValue(true) ได้
  //pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("📡 BLE พร้อมแล้ว! กดปุ่มขา 33 เพื่อส่งค่า NPK");
}

// ==========================================
// Loop
// ==========================================
void loop() {
  unsigned long currentMillis = millis();

  // ── ปุ่ม Deep Sleep (ขา 14) ──
  if (sleepBtnPressed) {
    sleepBtnPressed = false;
    if (digitalRead(SLEEP_BTN_PIN) == LOW) {
      Serial.println("Going to Deep Sleep...");
      lcd.clear();
      lcd.print("Sleep...");
      lcd.noDisplay();
      lcd.noBacklight();
      while (digitalRead(SLEEP_BTN_PIN) == LOW) delay(10);
      digitalWrite(Relay, HIGH);
      delay(100);
      gpio_hold_en(GPIO_NUM_13);
      gpio_deep_sleep_hold_en();
      esp_sleep_enable_ext0_wakeup(GPIO_NUM_14, 0);
      delay(100);
      esp_deep_sleep_start();
    }
  }

  // ── ปุ่มส่งค่า NPK (ขา 33) ──
  if (digitalRead(SEND_BTN_PIN) == LOW) {
    delay(50); // debounce
    if (digitalRead(SEND_BTN_PIN) == LOW) {
      if (!hasValidData) {
        Serial.println("⚠️ ยังไม่มีข้อมูลจากเซนเซอร์");
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("ยังไม่มีข้อมูล!");
        delay(1500);
      } else if (!deviceConnected) {
        Serial.println("⚠️ ยังไม่มีโทรศัพท์เชื่อมต่อ");
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("BLE ยังไม่เชื่อมต่อ");
        delay(1500);
      } else {
        // ส่งค่าล่าสุดผ่าน BLE
        uint8_t dataToSend[4] = { lastN, lastP, lastK, lastMoist };
        pCharacteristic->setValue(dataToSend, 4);
        if (deviceConnected) {
          pCharacteristic->notify();
        }
        delay(100);
        Serial.printf("📤 ส่งค่า BLE: N:%d P:%d K:%d Moist:%d\n",
                      lastN, lastP, lastK, lastMoist);

        // แสดง feedback บน LCD
        lcd.clear();
        lcd.setCursor(0, 0);
        lcd.print("Send Value");
        lcd.setCursor(0, 1);
        lcd.print("N:"); lcd.print(lastN);
        lcd.print(" P:"); lcd.print(lastP);
        lcd.print(" K:"); lcd.print(lastK);
        lcd.setCursor(0, 2);
        lcd.print("Moisture: "); lcd.print(lastMoist); lcd.print("%");
        delay(2000);
      }
      // รอปล่อยปุ่ม
      while (digitalRead(SEND_BTN_PIN) == LOW) delay(10);
    }
  }

  // ── อ่านค่าเซนเซอร์ทุก 5 วิ ──
  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;

    // ส่ง command อ่านผ่าน RS485
    digitalWrite(RE, HIGH);
    delay(10);
    Serial1.write(read_all, sizeof(read_all));
    Serial1.flush();
    digitalWrite(RE, LOW);
    delay(200);

    int i = 0;
    while (Serial1.available() && i < 25) {
      values[i++] = Serial1.read();
    }

    float temp = 0, humid = 0, ph = 0;
    int ec = 0, salinity = 0, n = 0, p = 0, k = 0;

    if (i >= 21) {
      temp     = (int16_t)((values[3]  << 8) | values[4])  / 10.0;
      humid    = (uint16_t)((values[5] << 8) | values[6])  / 10.0;
      ec       = (uint16_t)((values[7] << 8) | values[8]);
      ph       = (uint16_t)((values[17]<< 8) | values[18]) / 100.0;
      salinity = (uint16_t)((values[9] << 8) | values[10]);
      n        = (uint16_t)((values[11]<< 8) | values[12]);
      p        = (uint16_t)((values[13]<< 8) | values[14]);
      k        = (uint16_t)((values[15]<< 8) | values[16]);

      // อัปเดตค่าล่าสุด — รอให้กดปุ่มค่อยส่ง
      lastN     = (uint8_t)constrain(n, 0, 255);
      lastP     = (uint8_t)constrain(p, 0, 255);
      lastK     = (uint8_t)constrain(k, 0, 255);
      lastMoist = (uint8_t)constrain((int)humid, 0, 255);
      hasValidData = true;

      Serial.printf("N:%d P:%d K:%d Temp:%.1f Humid:%.1f EC:%d pH:%.2f\n",
                    n, p, k, temp, humid, ec, ph);

      // อัปเดต LCD
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("N:"); lcd.print(n);
      lcd.print(" P:"); lcd.print(p);
      lcd.print(" K:"); lcd.print(k);

      lcd.setCursor(0, 1);
      lcd.print("Temp:"); lcd.print(temp, 1); lcd.print("C");
      lcd.print(" H:"); lcd.print(humid, 0); lcd.print("%");

      int adc_value = analogRead(ANALOG_IN_PIN);
      float voltage_adc = ((float)adc_value * REF_VOLTAGE) / ADC_RESOLUTION;
      float voltage_in  = voltage_adc * (R1 + R2) / R2;
      float mapped_value = constrain((voltage_in - 10.8) * 100.0 / (12.0 - 10.8), 0, 100);

      lcd.setCursor(0, 2);
      lcd.print("Volt:"); lcd.print(voltage_in, 2); lcd.print("V");
      lcd.print(deviceConnected ? " BLE:ON" : " BLE:--");

      lcd.setCursor(0, 3);
      lcd.print("ADC:"); lcd.print(adc_value);
      lcd.print(" "); lcd.print(mapped_value, 0); lcd.print("%");

    } else {
      Serial.println("❌ Error: No data from sensor");
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print("Sensor Error!");
    }

    // Relay toggle
    if (currentMillis - relayMillis >= 20000) {
      relayMillis = currentMillis;
      digitalWrite(Relay, LOW);
      delay(50);
    }
  }
}
