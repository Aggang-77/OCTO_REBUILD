# 문어 게임 조작키 명세서 v1.0 — main 구현

## 조작 기준

문어의 몸통을 기준으로 앞뒤/좌우를 정의한다. 몸통의 국소 +Z 방향을 전방으로
사용한다. 물리 팔 번호는 +Z에서 45도 간격으로 진행하며, 0~7의 순서이다.
각 팔은 **펴기**와 **젓기**를 독립 키로 제어한다. 키를 동시에 누를 수 있다.

| 팔 | C++ arm 인덱스 | 펴기 | 젓기 |
|---|---:|---|---|
| 왼쪽 앞팔 | 7 | F | D |
| 오른쪽 앞팔 | 0 | J | K |
| 왼쪽 옆앞팔 | 6 | S | A |
| 오른쪽 옆앞팔 | 1 | L | ; |
| 왼쪽 옆뒤팔 | 5 | R | E |
| 오른쪽 옆뒤팔 | 2 | U | I |
| 왼쪽 뒤팔 | 4 | W | Q |
| 오른쪽 뒤팔 | 3 | O | P |
| 모든 빨판 해제 | 공통 | Space | — |

## 펴기 / 젓기

**펴기**를 누르면 길이 목표 배율 1.28, 곡률 목표 0 rad/m이고,
놓으면 길이 목표 0.70, 곡률 목표 3.6 rad/m이다.
두 목표 모두 물리 시뮬레이터의 하위 시간 단계에서 연속적으로 필터링된다.
즉, 키를 누른 순간 팔의 좌표가 바뀌지 않는다.

**젓기**를 누르면 몸통 국소 프레임에서 뒤쪽, 놓으면 앞쪽의 목표 자세로
복귀한다. 목표 범위는 ±60°로 두되 관절의 정확한 각도를 고정하지 않는다.
실제 각도는 물체와 바닥에 닿는지, 팔의 강성/관성에 따라 달라진다.
젓는 힘은 물리 월드에 가해지고, 몸통에 반대 반작용도 배분된다.

두 키는 독립적이다: F와 D를 동시에 누르면 왼쪽 앞팔을 뻗으면서
뒤쪽으로 젓는다.

## 자동 흡착 / 해제

게임의 C++ 월드는 팔마다 여러 개의 빨판 **후보 노드**를 사용하며,
표면 근접·밑면 방향·후보 노드 면적·상대 속도·안정 유지 시간 등을 확인한다.
현재 구현은 별도 메쉬 수준의 실제 빨판 접촉이나 표면 적분이 아니라
**XPBD 막대 노드를 이용한 근사 모델**이다.

- 바닥 접착: 팔을 펴는 동안 유지하며, 팔을 접을 때 먼 쪽부터 순차적으로 해제한다.
- 이동 물체 접착: 팔을 접어도 유지하여 물체를 당길 수 있으며, 한계 힘 초과 시 해제된다.
- Space 누름: 모든 팔의 모든 빨판 접착을 즉시 해제하며, 누른 동안 재흡착을 금지한다.
- Space 놓음: 자동 흡착 재허용, 약 180ms 동안 같은 후보 노드의 재흡착을 방지한다.
- 해제 시 물체의 속도는 임의로 초기화하지 않는다. 이동 중 놓으면 별도 던지기
  임펄스 없이 기존 관성으로 움직인다.

Space는 팔 조작과 동시에 사용 가능하다. 개별 물체만 선택해 놓는 기능은 없다.

## 구현 및 프로토콜

`game/scripts/demo.gd`가 물리 키보드 입력을 읽어
`step2` C++ 명령으로 직렬화한다. 한 팔의 전송 항목:
`animal arm activation curvature extension twist stiffness attach sweep`.
그 다음 드래그 정보 8개 항목과 전역 `release_all(0/1)`이 따라온다.
과거 테스트를 위해 기존 `step`은 계속 지원한다.

게임은 `reset ANIMALS SPACING 1`로 자동 흡착을 활성화한다.
순수 C++ 테스트 기본값에서는 기존 회귀 테스트를 보존하려고 꺼져 있다.

기존 원본 GameReady 메시 및 스켈레톤은 변경하지 않았다.
새 쉐이더/막은 main에 추가하지 않는다.

## 검증/한계

실행 검증 항목: C++ 물리/브리지 테스트, Godot 실물 키 이벤트를
통한 16개 키 직렬화 및 동시 입력·해제/Space 검증.

**남은 물리적 한계:** 이 구현은 빨판 표면이 실제로 얼마나 넓게 맞닿는지
정밀 면적 적분을 하지 않으며, 완전한 젓기 각도 제어나 3D 빨판
압력/박리 모델도 아니다. 문어의 몸통 방향은 현재 7개 노드 물리 케이지로
근사한다. 일반적인 게임 조작 프로토타입에 맞춘 1차 구현이다.

원본 GameReady GLB는 Git에 없으므로 모델이 장착된 Windows 환경의
전체 키 조작·충돌·던지기 플레이 테스트는 별도로 필요하다.

## 팔 힘 및 빨판 접착력 조정 (2026-11-15)

문어가 바닥이나 물체를 밀고 당길 때 힘이 약했던 문제를 줄이기 위해
C++ 공통 물리 세계의 기본 `WorldConfig`에 다음 배율을 추가했다.

- `arm_motor_strength = 4.0`: 팔 젓기의 위치 목표에 대한 구동력과
  단일 노드 구동력 상한을 이전 대비 4배로 확대한다.
- `sucker_strength = 3.0`: 바닥·이동 물체에 대한 여러 빨판 후보의
  파단력 임계값과 기존 수동 말단 접착 한계를 3배 확대한다.
- 두 배율은 각각 `0.1~12.0` 범위에서 설정 가능하며 비정상값을 거부한다.
  C++의 XPBD 접촉·반작용·반경 근사 구조는 그대로 사용한다.

실제 물체를 끌어오는 힘은 물체 질량, 마찰, 팔 자세, 부착점 개수 및
물리적 접촉 상태에 따라서도 달라진다. 설정 배율은 힘 배율이지
이동 거리·속도 또는 물리적 접촉력의 4배/3배 보장을 의미하지 않는다.

## Soft-body / reach-to-grip pass (2026-11-15)

- `WorldConfig::softness=5.0`: torso edge, arm axial and root,
  bending, shear and torsional *compliance* is increased about 5×
  over the original XPBD constraints. Torso volume compliance is
  increased more conservatively by sqrt(5) to avoid collapse.
  This is not a physical Young modulus measurement and stiffness
  cannot be inferred linearly from the multiplier.
- V1 hold-extend uses an axial target of **1.48×** instead of 1.28×;
  release target is **0.58×** rather than 0.70×. The C++ length
  bounds were adjusted to 0.55–1.50×. Those are target rest-length
  ratios, not a guarantee of actual stretched length.
- Soft torso/arms deform further under collision and strain. Local
  rendering uses the existing GameReady model and skeletal arms;
  actual full mantle *surface* volumetric skinning is still unimplemented.
- When extend is held without any grip, C++ applies downward bounded
  forces to distal arm nodes to seek a reachable floor. It does not
  teleport the octopus or create suction without real floor/rigid
  contact. After contact, it prioritizes nearby movable objects and
  falls back to floor adhesion after a shorter dwell. Space prevents
  all acquisition, even during seeking; detached stationary suction
  points still respect cooldown. If there is no reachable surface,
  forced attachment is physically impossible and not invented.
- Note: existing zero-input passive auto-suction behavior is maintained
  for backwards compatibility and historical tests.

## 2026-11-15: soft uncoiling and grip response

When the extend key is held, the C++ world advances
`Arm::uncoil_front` from 0 to 1 at a maximum of
`WorldConfig::uncoil_speed=2.0` of the arm length per second.
For each section with normalised arclength `u`, a smooth transition
around `u = uncoil_front` blends between high distal curl and
uncoiled curvature. The hold/release target is filtered and applied
via existing XPBD bend and Cosserat director constraints; motion
is physical and sequential, not an immediate skeletal pose change.
The arm's previous extend/retract target length ratios remain 1.48/0.58.

The first contacted sucker now records surface normal, tangent,
binormal and an approximate local wrap radius. The C++ surface-follow
motor steers nearby not-yet-gripped nodes along a local tangent circle
around a rigid contact or along the ground plane. Subsequent suction
contacts remain subject to surface proximity, dwell, relative speed,
Space suppression and force thresholds. There is **no** grasping
without contact or collision-free wrapping around distant objects.

A capped, dynamic upper/lower torso particle force pair mitigates
repeated rollovers; it adds no fixed kinematic orientation.
Default arm stroke motor multiplier is lowered from 4.0 to **2.2**;
automatic suction break-strength multiplier from 3.0 to **2.2**.

Existing GameReady surface textures get lower roughness and built-in
clearcoat at load time for a moist look, with no new custom shader.
This is **not simulated mucus fluid**, and actual cloth/skin volume
and exact contact patch integration remain future research.
