/* Blynk 정보와 Wi-Fi·MQTT 주소는 secrets.h 에 둔다 (secrets.h.example 복사 후 작성, Git 제외) */
#include "secrets.h"

/* Comment this out to disable prints and save space */
#define BLYNK_PRINT Serial

#include <Servo.h>
#include <BlynkSimpleEsp8266.h>
#include <ESP8266WiFi.h>
#include <PubSubClient.h>

// Your WiFi credentials.
char auth[] = BLYNK_AUTH_TOKEN;
// Set password to "" for open networks.
char ssid[] = WIFI_SSID;
char pass[] = WIFI_PASS;

// ===== MQTT 정보 =====
const char* mqtt_server = MQTT_SERVER;
WiFiClient espClient;
PubSubClient client(espClient);

// ===== 서보모터 =====
Servo myservo;                                        // 서보모터 선언
int pos = 0;                                               // 모터 위치를 확인하기 위해 변수를 선언

// ===== Blynk 콜백 =====
BLYNK_WRITE(V0){
  int value = param.asInt();
  if(value == 1) {
    pos = 30; // 회전각도 변경
    if(pos > 180) pos = 180;
    myservo.write(pos);
  }
}

BLYNK_WRITE(V1){
  int value = param.asInt();
  if(value == 1) {
    pos = 150; // 회전각도 변경
    if(pos < 0) pos = 0;
    myservo.write(pos);
  }
}

// ===== WiFi 연결 =====
void setup_wifi() {
  Serial.print("Connecting to ");
  Serial.println(ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, pass);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500); Serial.print(".");
  }
  Serial.println("\nWiFi connected");
  Serial.print("IP address : ");
  Serial.println(WiFi.localIP());
}

// ===== MQTT 메시지 콜백 =====
void callback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (unsigned int i=0; i < length; i++){
    msg += (char)payload[i];
  }

  Serial.print("MQTT 메시지 수신 [");
  Serial.print(topic); Serial.print("]: ");
  Serial.println(msg);

  if (msg == "off") {
    myservo.write(30); // 회전각도 변경
    Serial.println("MQTT: 서보 OFF (30도)");
  } else if (msg == "on") {
    myservo.write(160);
    Serial.println("MQTT: 서보 ON (160도)");
  }
}

// ===== MQTT 연결 유지 =====
void reconnect() {
  while (!client.connected()) {
        Serial.print("MQTT 연결 시도...");
    if (client.connect("NodeMCU_Client")) {
      Serial.println("연결 성공");
      client.subscribe("tars/sg90");
    } else {
      Serial.print("실패, 코드=");
      Serial.print(client.state());
      Serial.println("5초 후 재시도");
      delay(5000);
    }
  }
}

void setup()
{
  // Debug console
  Serial.begin(115200);

  // pinMode (servoPin, OUTPUT);           // 모터 제어핀을 출력으로 설정
  myservo.attach(5);                             // 모터 신호선: GPIO5 (NodeMCU D1)

  // Blynk 시작
  Blynk.begin(auth, ssid, pass, "blynk.cloud", 80);

  // MQTT 설정
  client.setServer(mqtt_server, 1883);
  client.setCallback(callback);
}

void loop()
{
  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  Blynk.run();
}
