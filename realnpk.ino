#include <WiFi.h>
#include <WiFiManager.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

#define RE 4
#define RXD2 17
#define TXD2 16

#define ANALOG_IN_PIN 36
#define REF_VOLTAGE 3.295
#define ADC_RESOLUTION 4096.0
#define R1 30000.0
#define R2 7500.0

#define BUTTON_PIN 14

#define SDA 21
#define SCL 22

unsigned long previousMillis = 0, relayMillis = 0;
const unsigned long interval = 5000;
bool statusRelay = false;
const String name = "ESP01";

const byte read_all[] = { 0x01, 0x03, 0x00, 0x00, 0x00, 0x08, 0x44, 0x0C };
byte values[25];

int Relay = 13;

volatile bool buttonInterrupt = false;

LiquidCrystal_I2C lcd(0x27, 20, 4);

void IRAM_ATTR handleButton() {
  buttonInterrupt = true;
}

void setup() {

  Serial.begin(9600);
  gpio_hold_dis(GPIO_NUM_13);
  gpio_deep_sleep_hold_dis();
  Wire.begin(SDA, SCL);
  lcd.init();
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("Soil Monitor");
  delay(2000);
  lcd.clear();

  pinMode(BUTTON_PIN, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(BUTTON_PIN), handleButton, FALLING);

  Serial1.begin(9600, SERIAL_8N1, RXD2, TXD2);

  pinMode(RE, OUTPUT);
  digitalWrite(RE, LOW);

  pinMode(Relay, OUTPUT);
  digitalWrite(Relay, LOW);

  WiFiManager wifiManager;
  wifiManager.autoConnect("ESP32_Soil_Config");
}

void loop() {

  unsigned long currentMillis = millis();

  if (buttonInterrupt) {
    buttonInterrupt = false;

    if (digitalRead(BUTTON_PIN) == LOW) {

      Serial.println("Going to Deep Sleep...");
      lcd.clear();
      lcd.print("Sleep...");
      lcd.noDisplay();
      lcd.noBacklight();
      while (digitalRead(BUTTON_PIN) == LOW) {
        delay(10);
      }

      
      // ปิด relay ก่อนหลับ
      digitalWrite(Relay, HIGH);
      delay(100);
      // lock ขาไว้
      gpio_hold_en(GPIO_NUM_13);
      gpio_deep_sleep_hold_en();

      esp_sleep_enable_ext0_wakeup(GPIO_NUM_14, 0);

      delay(100);

      esp_deep_sleep_start();
    }
  }

  if (currentMillis - previousMillis >= interval) {

    previousMillis = currentMillis;

    digitalWrite(RE, HIGH);
    delay(10);

    Serial1.write(read_all, sizeof(read_all));
    Serial1.flush();

    digitalWrite(RE, LOW);

    delay(200);

    int i = 0;

    while (Serial1.available() && i < 25) {
      values[i] = Serial1.read();
      i++;
    }

    float temp = 0;
    float humid = 0;
    int ec = 0;
    float ph = 0;
    int salinity = 0;
    int n = 0;
    int p = 0;
    int k = 0;

    if (i >= 21) {

      Serial.print("Raw Data (Hex): ");
      for (int j = 0; j < i; j++) {
        if (values[j] < 0x10) Serial.print("0");
        Serial.print(values[j], HEX);
        Serial.print(" ");
      }
      Serial.println();

      temp = (int16_t)((values[3] << 8) | values[4]) / 10.0;
      humid = (uint16_t)((values[5] << 8) | values[6]) / 10.0;
      ec = (uint16_t)((values[7] << 8) | values[8]);
      ph = (uint16_t)((values[17] << 8) | values[18]) / 100.0;
      salinity = (uint16_t)((values[9] << 8) | values[10]);
      n = (uint16_t)((values[11] << 8) | values[12]);
      p = (uint16_t)((values[13] << 8) | values[14]);
      k = (uint16_t)((values[15] << 8) | values[16]);

      Serial.printf("Temp: %.1f C | Humid: %.1f %%\n", temp, humid);
      Serial.printf("EC: %d uS/cm\n", ec);
      Serial.printf("pH: %.2f\n", ph);
      Serial.printf("Salinity: %d mg/L\n", salinity);
      Serial.printf("N: %d | P: %d | K: %d mg/kg\n", n, p, k);

    } else {

      Serial.println("Error: No data from sensor");
    }

    int adc_value = analogRead(ANALOG_IN_PIN);

    float voltage_adc = ((float)adc_value * REF_VOLTAGE) / ADC_RESOLUTION;
    float voltage_in = voltage_adc * (R1 + R2) / R2;

    Serial.print("ADC: ");
    Serial.println(adc_value);

    Serial.print("Measured Voltage = ");
    Serial.println(voltage_in, 2);

    float mapped_value = (voltage_in - 10.8) * (100.0) / (12.0 - 10.8);

    if (currentMillis - relayMillis >= 20000) {
      relayMillis = currentMillis;

      statusRelay = !statusRelay;
      digitalWrite(Relay, LOW);
      delay(50);
      Serial.println(statusRelay);
    }

    if (mapped_value < 0) mapped_value = 0;
    if (mapped_value > 100) mapped_value = 100;

    Serial.print(mapped_value, 2);
    Serial.println("%");

    // ===== LCD Display =====

    lcd.clear();

    lcd.setCursor(0, 0);
    lcd.print("N:");
    lcd.print(n);
    lcd.print(" P:");
    lcd.print(p);
    lcd.print(" K:");
    lcd.print(k);

    lcd.setCursor(0, 1);
    lcd.print("Temp:");
    lcd.print(temp, 1);
    lcd.print("C");

    lcd.setCursor(0, 2);
    lcd.print("Volt:");
    lcd.print(voltage_in, 2);
    lcd.print("V");

    lcd.setCursor(0, 3);
    lcd.print("ADC:");
    lcd.print(adc_value);
    lcd.print(" ");
    lcd.print(mapped_value, 0);
    lcd.print("%");
  }
}