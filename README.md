# Octopus simulator · 갯벌 콜로세움 / Character target lab

## 문어 + 미소녀 + 맵 통합 게임

**`PLAY_GAME.cmd`를 더블클릭하거나 Godot에서 F5**를 누르면
`scenes/octopus_game.tscn`이 실행됩니다. OCTO_REBUILD의 실제 GameReady 문어,
8개 촉수 근육 조작과 C++ 물리를 기존 미소녀 AI·부위 물리·갯벌 맵과 합쳤습니다.

이 로컬 병합판은 원본 `main`의 `5199960`까지 반영했습니다. 강화된 촉수 힘·흡착,
순차적으로 풀리는 촉수, 접촉면 따라가기, 몸통 안정화와 점성·형태 회복을 사용합니다.
촉수의 기본 뻗기/회수 길이는 1.48/0.58이며, 접지 후 젓기에서는 길이도 줄여 힘을 전달합니다.
젓기 범위는 기준 방향에서 27°이며, 앞·뒤의 좌우 다리는 중앙을 가로지르지 않게 제한합니다.
맵 지형·미소녀 포획·10초 목표·비밀 격투 모드는 같은 씬에서 유지합니다.

**승리 목표는 미소녀를 연속 10초 붙잡기입니다.** 모든 난이도가 동일하게 10초이며,
놓치거나 모든 구속이 끊어지면 즉시 0초부터 다시 시작합니다.
실제 촉수가 신체 물리 히트박스에 접촉해 붙잡으면 타이머가 시작됩니다.
붙잡는 촉수가 바뀌어도 다른 잡기가 유지되는 동안은 연속 포획이며, 거리만으로 포획하지 않습니다.

| 촉수 | 뻗기 (누르고 유지) | 뒤로 젓기 (누르고 유지) |
|---|---|---|
| 왼쪽 앞 / 오른쪽 앞 | R / U | E / I |
| 왼쪽 옆앞 / 오른쪽 옆앞 | W / O | Q / P |
| 왼쪽 옆뒤 / 오른쪽 옆뒤 | F / J | D / K |
| 왼쪽 뒤 / 오른쪽 뒤 | S / L | A / ; |

빈 팔은 뻗기 키를 놓으면 회수·말기, 젓기 키를 놓으면 앞쪽으로 돌아옵니다. 두 키는 함께 사용할 수 있습니다.
예를 들어 R+U로 앞의 두 다리를 뻗어 실제 접지를 기다린 뒤 E+I를 함께 누르면 젓습니다.
조작하지 않는 나머지 빈 다리는 낮은 마찰로 회수되고, 저절로 바닥에 다시 붙지 않습니다.
펴기 키를 유지하면 경사에서도 지지하며, 모든 빈 다리의 키를 놓으면 미끄러질 수 있습니다.
잡은 팔은 뻗기 키를 놓아도 유지되며, 잡기가 끊어지면 뻗기 키를 다시 눌러야 새로 잡습니다.
팔은 몸통 앞쪽에서 좌우 각각 22.5°·67.5°·112.5°·157.5°로 배치되며, 문어의 물리 크기와 원본 모델 크기를 모두 1.5배로 사용합니다.
실제 맵 정적 충돌 메시를 엔진에 전송한 뒤 라운드를 시작합니다.
**Space**는 모든 잡기와 바닥 흡착을 해제하며, 누르는 동안 재포획을 막습니다.
문어 **좌드래그**는 제한된 힘으로 당기기, **우드래그 / 휠**은 카메라 회전 / 확대입니다.
**F5** 초기화, **Esc** 일시정지, **C** 추적 시점, **F1~F4** 캐릭터, **1~3** 난이도입니다.
WASD는 문어 몸통의 직접 이동 키가 아니라 위 표의 촉수 키입니다.

Windows 문어 엔진은 `native/octo/octo_game_server.exe`에 함께 있습니다.
다시 빌드하려면 `tools/build_octopus.ps1 -Tests`를 실행합니다. 로컬 Zig 경로는
스크립트 기본값 또는 `-Zig`로 지정합니다. 결합 방식과 한계는 `native/octo/PROVENANCE.md`에 있습니다.
기존 캐릭터·맵·격투 실험실은 각 씬을 열어 F6으로 실행할 수 있습니다.

통합 검증:

```powershell
.\tools\build_octopus.ps1 -Tests
.\tools\build_octopus.ps1 -TerrainTrials # 30도 경사·요철·수직 턱의 한계 측정, 미달이면 실패 반환
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --max-fps 60 --script tests/test_octopus_merge.gd
.\.tools\godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --max-fps 60 --script tests/test_octopus_contact.gd
```

## 직접 조작 격투 모드

캐릭터 테스트 화면에서 **F10 / 격투 모드**를 누르거나 `scenes/hunter_fight_lab.tscn`을 열고 **F6**으로 실행합니다.
추가 `Girl_motion_2`, `Girl_motion_3`의 격투·방어·회피·승리 모션을 세 캐릭터에 리타기팅했습니다.

| 키 | 동작 |
|---|---|
| WASD / Shift | 카메라 기준 이동 / 달리기 |
| J | 잽 → 스트레이트 → 훅 연계. 동작 끝 부근의 다음 입력을 버퍼링 |
| K | 캐릭터별 킥 3종 순환. Lily는 전진 킥, Rin은 마르텔루, Aki는 왼발 킥부터 시작 |
| L / U | 무릎 공격 / 팔꿈치 엘보우. 엘보는 약 0.064초 선딜, 1초 후딜, 1.9초 재사용 간격 |
| I | 0번 Lily Orange: 펀치 4연타 / 1번 Lily: Armada → Martelo Do Chau / 2번 Rin: 얼굴 잡고 니킥 / 3번 Aki: 니킥 → 어퍼컷 |
| Q | 앞쪽 공격을 타이밍에 맞춰 패링 |
| E | WASD 방향 회피. 방향 입력이 없으면 뒤로 회피 |
| C | 대결 → 어깨 → 측면 시점을 부드럽게 전환 |
| Space | 슬라이딩 태클. 실제 발·정강이 접촉으로 피해를 주며, 빠른 다리 타격은 넘어뜨림. 낮은 장애물 아래로 통과 가능 |
| O | 상대 스파링 AI / 움직이지 않는 훈련 상대 전환 |
| B | 주황색 공격 박스와 파란색 피격 박스 표시 |
| R / P 또는 Esc | 양쪽 체력·위치·라운드 초기화 / 일시정지 |
| 0 / F1 / F2 / F3 | 0·1·2·3번 조작 캐릭터 선택. 0번은 F4로도 선택 가능. 상대는 별도 선택 |
| F10 | 문어 AI 실험실로 돌아가기 |

앞뒤 이동을 반전하면 제공된 턴 모션을 재생하면서 몸을 돌립니다. 슬라이딩은 실제 컨트롤러 충돌체와
최종 스켈레톤의 피격 박스 높이를 함께 낮추며, 무적 판정은 주지 않습니다.

손·발·정강이·무릎·팔꿈치에 **10개 공격 Area3D**, 머리·몸통·골반·팔다리에 **15개 피격 Area3D**를 별도로 두었습니다.
공격 구간에서만 켜지는 캡슐/구 공격 박스를 이전 자세부터 현재 자세까지 잘게 나눠 실제 피격 박스와 겹치는지 검사합니다.
거리만으로 체력을 깎지 않으며, 벽 너머 타격과 한 타격 구간의 중복 피해를 막습니다. 4연타는 구간별 한 번씩 맞을 수 있습니다.
피격 박스는 원본 모션과 구속·넘어짐 물리가 모두 반영된 최종 몸을 따라갑니다.

접촉 기록에는 `attack_part`, `hurt_part`, `move`, `damage`, `position`, 공격자·피격자를 따로 남깁니다.
머리는 기본 피해의 1.4배, 몸통·골반은 1배, 팔은 0.65배, 다리는 0.75배입니다.
팔을 먼저 건드리면 팔 피격으로 판정되므로 하이킥도 거리·각도가 맞아야 머리에 닿습니다.

맞은 **상대 캐릭터**가 실제 `Big Hit To Head` 또는 `Hit To Body` 모션을 처음부터 재생합니다.
머리 3종, 몸통 2종을 번갈아 사용하고, 강한 머리 타격과 KO는 짧은 피격 반응 뒤 물리적으로 넘어집니다.
일반 피격 스턴은 몸통 0.30초 / 머리 0.36초로 남겨두고, 공격이 거의 동시에 닿으면 최대 0.075초 동안 서로 타격할 수 있습니다.
일반 펀치·킥 후딜은 0.08~0.15초이며, 주먹 판정은 작은 구로 좁혔습니다. 킥은 공격별 발걸음·활성 구간으로 더 긴 실제 리치를 갖습니다.
U 엘보는 약 0.064초의 빠른 선딜 대신 1초 후딜과 1.9초 재사용 간격을 두어 연속 사용을 막습니다.

1초 안에 연속 2회 맞은 뒤에는 **Q/E로 연타 중 피격 스턴을 끊고 패링·회피**할 수 있습니다.
누적 피격 반응을 최소 0.12초 겪은 뒤, 스태미나 20을 쓰며 탈출 재사용 간격은 2초입니다.
탈출 시작 0.16초는 가벼운 타격에 경직되지 않지만 피해는 받습니다. 이때 맞으면 깨끗한 회피 성공 보너스도 받지 않습니다.
단발 피격 스턴과 강한 타격·넘어뜨림은 유지합니다. 화면에 탈출 가능 여부를 표시합니다.

슬라이딩은 한 번의 동작에서 같은 상대에게 한 번만 피해를 줍니다. 실제 다리 접촉 시 전진 속도 2.8m/s 이상이고 상대가 지상에 있으면 피격 반응 뒤 물리적으로 넘어뜨립니다.

패링 동작은 0.68초이며, 0.08~0.48초에 앞쪽 상체로 들어오는 실제 접촉을 받아냅니다. 방어 중 양쪽 팔에 옅은 반투명 막을 표시합니다.
회피는 시작 위치의 몸 형태에 공격이 들어왔고 이동한 실제 몸은 맞지 않았을 때 성공합니다. 회피 자체에는 무적이 없습니다.
회피 중에는 원래 텍스처를 유지한 채 몸이 잠시 반투명해지며 깜빡이고, 피격 시에는 약 0.2초 동안 옅은 붉은 효과가 나타납니다.
**패링·회피 성공 시 1.2초 안에 쓰는 다음 공격 1회의 선딜만 1.45배 빠르게 재생**합니다.
타격 속도·피해량은 그대로이며 빈 패링·빈 회피에는 보너스가 없습니다.

0번은 제공된 `Lily_Orange_Restyle`의 주황 단발·롱 코트 모델입니다. 원본 얼굴 표정과 헤어 컬러·노멀 텍스처를 유지하고 공통 게임 모션, 코트 단·머리 보조 본, 부위 물리를 연결했습니다.
0번 K는 미들킥 → 회전킥 → 마르텔루로 순환합니다. 기존 1·2·3번 번호와 킥 구성은 유지합니다.
0번 코트는 허리 아래 3~8cm 여유, 등판 약 3~5cm 여유를 연결해 보정하고, 중간·옷단 움직임을 부드럽게 조정했습니다.
1번 I는 새 FBX 두 동작을 연결한 회전 킥 연계입니다. 첫 타는 왼발, 다음 타는 오른발 접촉으로 각각 한 번 판정하며, 첫 타 18 / 마무리 26의 기본 피해를 사용합니다.

Rin의 잡기는 손이 머리 히트박스에 실제로 닿아야 연결됩니다. 두 손과 머리 사이의 양방향 물리 스프링을 걸고 니킥 후 해제합니다.
팔 길이 밖의 상대를 이동시키지 않으며 잡기가 빗나가면 연계가 끝납니다. Aki의 연계와 Lily의 4연타는 각 타격 구간을 별도로 판정합니다.
체력 0이면 KO로 끝나고 승자는 제공된 춤 세리머니 뒤 승리 자세를 유지합니다. 동시 KO는 무승부이며 R로 초기화합니다.
문어의 포획 승리 조건과는 별도입니다.

재사용 시 `target.enable_fighter(&"player", team)` 또는 `&"sparring"`, `&"dummy"`를 사용합니다.
기존 자율 도주·포획 AI는 격투 컨트롤을 켜지 않은 캐릭터에서 그대로 실행됩니다.
`fighter.strike_landed(contact)`, `hit_received(contact)`, `reaction_started(clip, hurt_part)`, `knocked_out(attacker)`로 연결합니다.
공격 피해량·속도·활성 구간·사용 부위는 `scripts/hunter/hunter_combat_moves.gd`에서 조정합니다.
전용 검증은 `tests/test_combat.gd`, `tests/test_combat_defense.gd`, `tests/test_zero_character.gd`, `tests/test_combat_effects.gd`, `tests/test_pressure_slide.gd`, `tests/test_fight_navigation.gd`를 `godot --headless --path . --fixed-fps 60 --script`로 실행합니다.

## 새 맵에서 기존 캐릭터 테스트

`scenes/tidal_hunter_lab.tscn`을 열고 **F6**으로 실행합니다. 기존 실험실의 캐릭터 선택,
난이도, 포획·엘보우·검격, 부위 구속, 질량 변경, 넘어짐, 일시정지를 같은 코드와 UI로 사용합니다.
`scripts/map/tidal_hunter_lab.gd`는 기존 `scripts/hunter_lab.gd`를 상속해 배경·초기 위치·지형 위 촉수 배치를 연결합니다.
캐릭터·전투·구속·물리 시스템과 원래 실험실 씬을 재사용합니다.

도주 후보는 실제 바닥 높이를 따라 짧은 구간으로 검사합니다. `floor_max_angle` 이내의 경사는
이동 가능한 바닥으로 처리하고, 벽·급경사·지지면이 끊기는 경로는 제외합니다.
촉수는 지면 아래의 피벗 대신 실제 끝의 노출된 윗면을 시야 대상으로 사용합니다.
클릭한 촉수와 자동 접근 촉수도 갯벌 높이를 따라가며, 물리적으로 잡힌 촉수의 앵커는 그대로 둡니다.

기상 모션을 시작할 때 기본 자세를 보행·대기로 전환하고, 원샷에 가려진 동안에도 그 전환을 계속 진행합니다.
기상 종료 시 이전의 넘어진 자세가 잠깐 다시 섞이는 현상을 막으며, 새로운 실제 충격에 의한 넘어짐은 유지합니다.
가려진 입력의 시간 진행은 [Godot AnimationNodeSync](https://docs.godotengine.org/en/stable/classes/class_animationnodesync.html)의
`sync` 설정을 사용합니다.

맵 소품은 이 통합 씬에서만 환경 레이어 **1**과 소품 레이어 **16**에 함께 등록됩니다.
따라서 기존 캐릭터의 충돌 설정을 바꾸지 않고 몸·검격 테스트용 촉수와 소품이 충돌합니다.
Space 일시정지는 맵 소품의 물리도 함께 멈춥니다.

- **갯벌 맵 둘러보기**: 배경 전체와 소품 물리 미리보기로 이동합니다.
- **기존 실험실**: 원래의 격자 바닥 테스트 씬으로 이동합니다.
- `scenes/tidal_colosseum.tscn`: 캐릭터 없는 맵 미리보기입니다. 상단 **캐릭터 테스트**로 돌아옵니다.
- `scenes/tidal_colosseum_environment.tscn`: 게임에 인스턴스할 배경 씬입니다. 편집기에서도 지형·아치·에셋이 보입니다.

약 56m 지름의 둥근 해안 지형에 36구간의 무너진 2층 아치, 계단식 관람석, 젖은 갯벌,
중앙 조수 웅덩이와 물길을 배치했습니다. 제공된 두 에셋 팩에서 바위·풀·고사목·해초·난파선과
항아리·통·조개·닻 등을 사용했습니다. 움직이는 소품 48개에는 실제 볼록 충돌체, 질량,
마찰, 연속 충돌, 물속 감쇠와 근사 부력을 적용했습니다. 장식 식물은 충돌이 없고,
아치·관람석·큰 바위·고사목·난파선은 고정 충돌체입니다.

맵 미리보기에서는 **우드래그 / 휠**로 회전·확대, **WASD**로 이동합니다.
**좌드래그**로 소품을 힘 기반 스프링으로 집고, 잡은 상태에서 **휠**로 거리를 조절하거나
**Space**로 던집니다. **R**은 소품 재배치, **1 / 2 / 3**은 전체·바닥·소품 시점,
**B**는 실제 소품 충돌체, **Tab**은 UI 표시를 전환합니다.
캐릭터 테스트 씬에서는 기존 단축키가 그대로 우선합니다.

배경 씬의 `SpawnPoints/OctopusSpawn`에 문어를 배치하면 됩니다.
`HunterSpawn`, `ExitSpawn`, `CameraFocus`도 별도로 마련했습니다.
실제 문어 강체의 충돌 마스크에는 환경 **1**, 캐릭터 히트박스 **4**, 소품 **16**을 포함하세요.
물 효과는 소품용 근사치이며, 유체 해석이나 조수 높이 변화는 구현하지 않았습니다.

지형과 건축의 생성 파라미터는 `scripts/map/tidal_arena.gd`에서 조정한 뒤 다시 베이크합니다.
생성기는 선택한 원본 모델이 이미 임포트되어 있다는 전제입니다.

```powershell
godot --headless --editor --path . --import
godot --headless --path . --script tools/build_tidal_map.gd
godot --headless --path . --fixed-fps 60 --script tests/test_tidal_map.gd
godot --headless --path . --fixed-fps 60 --script tests/test_tidal_hunter_lab.gd
godot --headless --path . --fixed-fps 60 --script tests/test_terrain_evasion.gd
godot --headless --path . --fixed-fps 60 --script tests/test_recovery.gd
```

에셋 라이선스는 `assets/environment/underwater/LICENSE.txt`와
`assets/environment/nature/LICENSE.txt`에 보존했습니다.

## 기존 독립 실험실

제공된 세 캐릭터와 Gril_motion 모션으로 만든 독립 자율 타겟입니다.
Godot에서 `project.godot`를 열고 `scenes/hunter_lab.tscn`을 선택한 뒤 **F6**으로 실행하세요.
**F5**는 위의 문어·미소녀 통합 게임을 실행합니다.
실제 문어 모델 대신 테스트용 보라색 촉수를 표시합니다. 잡히면 몸통을 감싸고, 풀려나면 감은 형태를 해제합니다.

## 캐릭터 선택

왼쪽 **CHARACTER SELECT**에서 세 모델 중 하나를 고르거나 **F1 / F2 / F3**를 누르세요.

| 선택 | 원본 | 변환 |
|---|---|---|
| Lily | Character.zip / Character.ma | Maya ASCII의 메시·UV·본 바인드 포즈·스킨 가중치를 데이터로 읽어 변환 |
| Rin | FBX_with_Atlas.zip | 원본 FBX와 아틀라스 재질 사용 |
| Aki | School_Girl_Aki.zip | 원본 GLB의 얼굴·헤어·의상 재질 사용 |

첨부한 프로필 그림 순서와 게임 캐릭터 번호를 **1번 Lily / 2번 Rin / 3번 Aki**로 연결했습니다.

| 번호 | 머리색 | 눈동자 | 추가 반영 |
|---|---|---|---|
| 1 · Lily | 붉은 기가 도는 어두운 갈색 | 붉은 분홍색 | 연분홍 블라우스·소매, 붉은 리본, 검정 장식 |
| 2 · Rin | 주황색 | 파랑·하늘색 | 흰자·속눈썹·입을 공유 머리색 아틀라스 처리에서 제외 |
| 3 · Aki | 검정색 | 보라색 | 기존 흰색 세일러 의상 유지 |

색상은 `scripts/hunter/character_appearance.gd`에서 관리합니다. 원본 모델·텍스처를 덮어쓰지 않고
재질로 적용하며, 원래 명암·알파·눈 하이라이트를 보존합니다. Lily는 원본 메시에서 사용되지 않던 홍채
텍스처 대신 기존 눈 표면에 홍채를 그립니다. 이때 눈 위·아래의 UV 경계를 잇는 별도 좌표를 사용해
홍채가 중간에서 갈라지지 않게 합니다. 원래 정점·본·스킨 가중치는 유지합니다.
Rin은 같은 아틀라스에 들어 있는 흰자를 주황색으로 칠하지 않습니다.

제공한 그림 원본은 `assets/ui/portraits/lily.png`, `rin.png`, `aki.png`에 그대로 보관했습니다.
나중에 프로필 UI에서 `HunterAnimation.CHARACTERS[index]["portrait"]` 경로로 사용할 수 있습니다.

세 모델은 같은 AI와 난이도를 사용하며, 캐릭터를 바꾸면 해당 캐릭터의 테스트 상태를 초기화합니다.
각 모델의 키를 약 1.65m로 맞추고 오른손과 손가락 본에 같은 모션 세트를 리타기팅했습니다.

## 세 난이도

| 단계 | 이동 | 대응 | 포획 목표 유지 시간 |
|---|---|---|---|
| 1 | 느린 도주, 최대 2 m/s | 공격 없음 | 8초 |
| 2 | 빠른 도주, 최대 5 m/s | 잡힌 상태에서만 엘보우 → 구속 해제 시도 → 재도주 | 12초 |
| 3 | 도주와 거리 확보, 최대 4.4 m/s | 가까워지는 절단 가능한 촉수에 검격, 잡히면 엘보우 | 16초 |

속도·가속도·반응 시간·감지 거리·피해량·재사용 시간·스태미나·구속 해제 강도는
`assets/hunter/level_1.tres`부터 `level_3.tres`에서 수정합니다.
스태미나가 부족하면 느려지며 회복합니다. 강한 구속은 엘보우 한 번으로 풀리지 않을 수 있습니다.

## 테스트 화면

- **1 / 2 / 3**: 난이도 선택 및 초기화
- **T**: 가상 위협 켜기/끄기
- **A**: 가상 촉수의 자동 접근 켜기/끄기
- **G**: 즉시 포획 입력. 1단계는 유지, 2단계 이상은 엘보우로 저항
- **H**: 강한 구속으로 포획. 엘보우로 풀리지 않는 포획 상황을 확인
- **강한 구속으로 테스트** 체크: G 버튼에 사용할 구속 강도 선택
- **U**: 구속 해제
- **R**: 초기화
- **마우스 좌클릭**: 바닥에 가상 위협 배치
- **우드래그 / 휠**: 카메라 회전 / 확대
- **C**: 캐릭터 추적 시점 켜기/끄기
- **Space**: 캐릭터 시뮬레이션 일시정지

## 양방향 물리와 구속

외부 접촉·구속이 없을 때 몸은 원본 모션을 그대로 재생합니다. 평소 발의 바닥 접촉은 물리 자세 보정을 켜지 않습니다.
외부 물체에 닿거나 잡히면 해당 부위와 이를 지지하는 관절에만 물리 결과를 부드럽게 섞고, 해제 후 원래 모션으로 돌아갑니다.
머리·몸통·골반·좌우 상완/전완/손/허벅지/정강이/발의 **15개 RigidBody3D**, 총 약 **56.4kg**을 관절로 연결했습니다.
각 부위의 캡슐 충돌체에 외부 물체가 닿거나 충격을 가하면 실제 강체가 반응하며, SkeletonModifier3D가 그 결과를 스킨 메시와 손의 검에 반영합니다.

유한한 힘·토크를 내는 구동기가 모션을 따라가려 합니다. 부위를 잡으면 모션을 끄는 대신,
움직이려는 힘과 구속의 스프링·감쇠·질량이 경쟁합니다. 약한 촉수는 밀려나고, 강하게 지지된 촉수는 팔의 움직임을 줄입니다.
구속 접촉점에는 캐릭터와 외부 강체에 **같은 크기·반대 방향의 힘**을 적용하며, 각 질량중심에서 떨어진 접촉점의 회전 반작용도 포함합니다.
구속 중에도 공격을 시도하며 가동성과 추종 오차에 따라 재생 속도·게임상 위력·탈출력이 줄어듭니다. 부위를 이진 값으로 잠그지 않습니다.

오른쪽 **TWO-WAY PHYSICS** 패널에서 시험하세요.

- **J / K**: 오른팔 / 왼팔을 물리 촉수 말단에 연결
- **V**: 3단계에서 구속 중 검격 시도
- **P**: 선택한 부위에 충격량 입력
- **F**: 물리적으로 넘어짐 → 자동 기상 테스트
- **검격 높이** 선택: 가상 촉수 끝을 0.45 / 0.95 / 1.55m에 배치. 잡힌 상태에서는 실제 구속점 높이를 사용
- **방향키**: 촉수 말단의 지지 지점을 이동해 당기기
- **질량 슬라이더**: 실제 촉수 말단 강체를 2~40kg으로 변경
- **B**: 실제 물리 히트박스 표시
- **U**: 모든 부위의 물리 구속과 전신 포획 해제
- 왼쪽 **강한 구속** 체크는 새 구속의 스프링·최대 힘도 높입니다.

보행 경로와 균형은 AI 루트 컨트롤러가 보조하는 하이브리드 방식입니다. 정밀한 근골격 모델은 아닙니다.
관절 한계는 게임용 근사치이며, 실제 문어의 질량·물리 시간 간격·구속 강도에 맞춰 조정해야 합니다.
무릎·팔꿈치는 한 방향으로 굽혀지는 힌지로, 어깨는 제한된 볼 관절로 연결합니다.
몸통·목·고관절·손목·발목은 축별 굽힘·회전 범위를 제한합니다. 충격 때는 제한을 넘는 각속도를 억제하고,
표시되는 스켈레톤에도 같은 제한을 적용합니다. 강체 솔버에는 큰 충격 직후 작은 시간 간격의 오차가 남을 수 있습니다.
넘어짐 중에는 연결되지 않은 몸 부위끼리도 충돌합니다.
강한 충격량이나 지속적인 큰 당김으로 균형을 잃으면 구동 힘을 낮추고 전신 물리로 넘어집니다. 이후 `get_up` 모션으로 기상하며,
강하게 몸통이 구속된 동안은 기상을 기다립니다. `target.knock_down(impulse, part)`로 게임 이벤트에서 직접 넘어뜨릴 수도 있습니다.

치마는 세 모델 모두 허리에 고정한 8방향의 **중간 → 치맛단 2단 체인**을 추가했습니다.
관성·감쇠·회전 제한을 적용하고, 실제 최종 다리 자세 바깥쪽으로 밀어내 관통을 줄입니다.
다리가 올라올 때 치마 패널을 들어 올리고, 촘촘히 나눈 치마 면 전체에 최종 다리 위치를 사용하는 충돌 보정을 적용합니다.
2·3번은 다리 굵기에 맞춰 충돌 범위와 흔들림을 작게 하고 감쇠를 높여, 평상시 치마가 과하게 떠 있지 않도록 조정했습니다.
이는 의상용 보조 본 물리이며, 몸과 촉수 사이의 양방향 강체 구속과는 별도로 움직입니다.

머리카락은 두피를 고정한 채 앞머리·옆머리·뒷머리를 8방향, 각 3단의 독립 체인으로 나눴습니다.
걷기·달리기·회전·넘어짐 때 관성으로 흔들리며, 앞머리는 작게, 긴 뒷머리는 더 크게 움직입니다.
얼굴과 어깨 주변의 간단한 충돌 보정 및 각도 제한을 포함합니다.

3단계 검격은 **A**로 촉수를 접근시키거나, 캐릭터 앞 약 2m 이내에 위협을 배치하면 확인할 수 있습니다.
위협 HP가 0이 되면 절단 처리됩니다. `T`로 다시 켜면 회복됩니다.

검은 `RightHand`의 BoneAttachment3D에 연결하고 손바닥과 중지 관절의 방향을 기준으로 배치합니다.
손잡이는 손 안쪽에, 검날은 손에서 바깥으로 뻗습니다. 검격은 기존 모션의 2.6배 속도로 약 0.65초에 끝나며,
상체 각도와 팔 조준을 촉수의 실제 높이에 맞추고, 짧은 전진 동작을 더했습니다.
물리가 반영된 **실제 검날의 이전·현재 위치를 잇는 경로**로 타격을 검사하며, 한 번 휘두를 때 같은 촉수는 한 번만 맞습니다. 벽 너머는 타격하지 않습니다.
절단 가능한 촉수 강체는 검격 동안 공격 팔의 충돌 저항을 줄이되, 명시적으로 잡힌 팔의 구속력과 반작용은 유지합니다.
검날을 따라 길고 반투명한 잔상이 생성되고, 한 번 휘두른 **궤적 전체가 유지된 뒤 동시에 서서히 투명해져 사라집니다**.
밝은 가장자리·발광·끝점 확장·적중 섬광은 줄여서 과하게 튀지 않게 했습니다.
점마다 시간차를 두고 끝부터 지우지 않습니다. 적중 시에는 섬광을 표시합니다.

## 나중에 문어와 연결

1. `scenes/hunter_target.tscn`을 게임 맵에 인스턴스합니다.
2. 문어 몸통 또는 각 촉수 끝의 자식으로 `HunterThreat` 노드를 추가합니다.
3. 실제 촉수의 충돌/붙잡기 성공 시 `target.try_capture(threat, restraint_strength)`를 호출합니다.
4. 손을 놓거나 촉수가 떨어지면 `target.release_capture(threat)`를 호출합니다.
5. `HunterThreat.cut_received`, `severed`, `escape_impulse`를 실제 촉수 피해·절단·밀림에 연결합니다.
6. `HunterTarget.objective_completed(result, score)`를 승패 시스템에 연결합니다.

### 물리 촉수와 부위별 연결

물리 히트박스는 `hunter_hitboxes` 그룹에 있고 `hunter_part`, `hunter_target` 메타데이터를 제공합니다.
문어가 실제 부위를 접촉했을 때 다음처럼 연결할 수 있습니다.

```gdscript
func grab_hitbox(hitbox: RigidBody3D, tentacle_body: RigidBody3D, contact: Vector3) -> int:
    var actor: HunterTarget = hitbox.get_meta("hunter_target")
    var part: StringName = hitbox.get_meta("hunter_part")
    return actor.physics_rig.attach_grip(part, tentacle_body, contact,
        1400.0, 55.0, 400.0, 1.5)
    # 위 값은 스프링 N/m, 감쇠 N·s/m, 최대 힘 N, 끊어지는 거리 m입니다.
```

`attach_grip`는 `RigidBody3D`에 직접 반작용을 줍니다. `PhysicalBone3D`도 지원하며,
별도 촉수 물리 솔버를 쓴다면 외부 Node3D에 `receive_contact_force(force, world_point, delta)`를 구현해
동일한 힘을 해당 솔버의 접촉점에 반영하세요. 콜백의 force는 외부 촉수에 작용하는 N 단위의 힘입니다.
단순히 위치만 바꾸는 Node3D에는 물리 반작용이 자동으로 생기지 않으므로 이 어댑터가 필요합니다.

`apply_part_impulse(part, impulse, world_point)`로 부위에 충격량(N·s)을 입력하고,
`release_grip(id)`, `release_grips_for(external)`, `clear_grips()`로 구속을 해제합니다.
부위 ID는 `pelvis`, `torso`, `head`, `left_upper_arm`, `left_forearm`, `left_hand`, `left_thigh`, `left_shin`, `left_foot`과 대응하는 `right_...`입니다.
질량은 `set_part_mass(part, kilograms)`, 구동 힘은 `muscle_strength`에서 조정할 수 있습니다.

기본 레이어 비트는 환경 **1**, AI 루트 **2**, 부위 히트박스 **4**, 물리 촉수 **8**입니다.
물리 촉수의 마스크에 **4**를 포함하세요. 캐릭터의 `physical_hitbox_layer`, `physical_collision_mask`로 변경할 수 있습니다.
단일 팔 구속은 포획 승리로 자동 처리하지 않습니다. 전신 포획이 성립하면 기존 `try_capture`를 추가로 호출해 목표 타이머를 시작하세요.
그때 HunterThreat의 `physics_anchor`를 실제 촉수 말단 강체에 지정하면 몸통의 물리 구속도 연결됩니다.

```gdscript
@onready var target: HunterTarget = $HunterTarget
@onready var tip: HunterThreat = $Octopus/TentacleTip/HunterThreat

func _ready() -> void:
    target.set_difficulty(3)
    target.objective_completed.connect(_on_target_result)
    tip.severed.connect(_on_tentacle_severed)

func on_tentacle_grab_contact() -> void:
    target.try_capture(tip, tip.restraint_strength)

func _on_tentacle_severed(_attacker: Node3D) -> void:
    target.release_capture(tip)
    # 여기에 실제 촉수 메시/물리 절단 처리를 연결합니다.

func _on_target_result(result: StringName, score: int) -> void:
    if result == &"captured":
        print("문어 포획 목표 달성: ", score)
    elif result == &"escaped":
        print("타겟 탈출: ", score)
```

`try_capture`는 문어 쪽에서 접촉을 검사한 뒤 보내는 입력입니다. 포획 여부를 거리만으로 자동 판정하지 않습니다.
몸통 위협은 `is_tentacle = false`, 절단 불가능한 위협은 `severable = false`로 설정하세요.
자체 어댑터를 쓰려면 `hunter_threats` 그룹에 등록하고 `get_threat_data(target)`를 구현해도 됩니다.
필드는 `position`, `velocity`, `active`, `is_tentacle`, `severable`, `radius`, `weight`이며,
검격 수신에는 `receive_cut(damage, attacker) -> bool`, 엘보우에는 `receive_escape_impulse(power, target)`를 제공합니다.
촉수 끝의 실제 타격점은 `get_cut_position()` 또는 데이터의 `cut_position`으로 전달하고, `cut_radius`(기본 0.20m)를 촉수 굵기에 맞춥니다.
`HunterThreat`에서는 `physics_anchor`의 실제 위치를 사용하며, 앵커가 없으면 노드 위치에 `aim_offset`을 더합니다.

### 맵과 이동

`safe_zone`에 탈출 지점을 지정하면 인지 후 그쪽을 향해 이동하며, 도착 후 1.5초 유지하면 탈출합니다.
32개 이동 후보에서 모든 감지 위협의 예상 위치, 장애물, 벽과 거리, 진행 방향과 탈출 지점을 비교합니다.
시야는 `environment_mask`로 검사합니다. 테스트 씬은 로컬 회피를 사용합니다.
실제 맵에 베이크된 `NavigationRegion3D`가 있으면 해당 맵의 경로를 사용합니다.
큰 맵으로 옮길 때는 `arena_bounds_enabled`를 끄거나 `arena_bounds`를 새 맵에 맞추세요.
실제 문어의 몸체/촉수 충돌 레이어는 환경 레이어 1과 분리하고 어댑터로 감지시키는 구성을 권장합니다.

### 승리 조건과 저장 가능한 값

`target.get_target_data()`는 ID, 진영, 우선순위, 체력, 속도, 난이도, 스태미나,
구속 여부, 포획 진행도, 결과와 점수를 반환합니다.
`Objective`의 `target_id`, `target_priority`, `max_health`, `capture_score`, `escape_penalty`를 조정할 수 있습니다.
체력이 0이면 무력화되지만, 문어는 여전히 포획 시간을 채워야 합니다.
포획이 끊기면 진행도가 줄어듭니다. 최종 결과는 한 번만 발생하고 초기화 전까지 유지됩니다.

## 파일과 검증

- `scenes/hunter_target.tscn`: 재사용할 여자 캐릭터
- `scripts/hunter/`: AI, 모션, 위협 어댑터, 목표 컴포넌트
- `assets/characters/lily.glb`, `rin.glb`, `aki.glb`, `lily_orange.glb`: 각 모델과 공통 42개 모션. Lily·Lily Orange는 새 킥 2개와 연결 클립을 포함해 45개
- `assets/characters/*_motions.json`: 리타기팅 모션 길이와 본 매핑 수
- `scripts/hunter/hunter_weapon.gd`: 손 부착 검과 검 궤적
- `scripts/capture_preview.gd`: 문어 포획 테스트용 촉수 표시
- `tools/prepare_characters.py`: 세 모델의 Blender 변환·리타기팅 재현 스크립트
- `tools/maya_ascii_mesh.py`: Maya ASCII 메시·UV·스킨 데이터 전용 파서. 문서 내부 MEL은 실행하지 않음
- `source_assets/`: 제공 원본을 푼 로컬 보존 폴더, Godot 임포트 제외
- `.tools/`: 로컬 변환 도구·로그·검사 결과, Godot 임포트 및 Git 제외

Godot 실행 파일로 다음 명령을 실행하면 행동 통합 검사를 수행합니다.

```powershell
godot --headless --path . --fixed-fps 60 --script tests/test_hunter.gd
godot --headless --path . --fixed-fps 60 --script tests/test_lab.gd
godot --headless --path . --fixed-fps 60 --script tests/test_physics.gd
godot --headless --path . --fixed-fps 60 --script tests/test_motion.gd
godot --headless --path . --fixed-fps 60 --script tests/test_secondary.gd
```

기존 캐릭터·검·AI와 실제 화면 조작 외에, 부위 충돌·구속 반작용·외부 강체 이동·구속 중 공격·기본 자세·헤어색을 검증합니다.
추가 검사는 비접촉 달리기의 원본 자세 일치, 세 캐릭터의 낮음/중간/높음 실제 검격, 치마 안정성,
물리적 넘어짐과 기상, 한 획 전체의 동시 잔상 페이드를 확인합니다.

모션은 세 모델과 Mixamo FBX의 본 이름·휴식 자세 차이를 맞춰 베이크했습니다.
이동은 물리 바디가 담당하고 모션의 수평 루트 이동은 제거했습니다.
AnimationTree가 실제 이동 속도에 따라 대기·조깅·질주를 섞고, 공격은 별도 원샷으로 재생합니다.
타격은 물리가 반영된 검날의 경로와 실제 촉수 끝의 접촉을 확인합니다.
본격적인 복잡한 맵과 실제 촉수 물리에 대한 수치 조정은 통합 후 필요합니다.

구현에 참고한 Godot 공식 문서: [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html),
[3D 형식 임포트](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html).
