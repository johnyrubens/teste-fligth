extends CharacterBody2D

@export var accel: float = 700.0
@export var max_speed: float = 170.0
@export var damp: float = 70.0

@export var rotation_speed: float = 3.0        # stick em alta velocidade
@export var rotation_speed_low: float = 4.5    # D-pad em baixa velocidade
@export var low_speed_threshold: float = 35.0

@export var deadzone: float = 0.20

# strafe vertical com L1/R1
@export var strafe_multiplier: float = 0.65    # 0.4..0.9

# troca sprite para "frente" quando subir/descer
@export var tex_side: Texture2D
@export var tex_front: Texture2D

# quique ao colidir
@export var bounce_factor: float = 0.5         # 0 para parar seco
@export var wrap_margin: float = 16.0

# triggers (L2/R2) para flip contextual
@export var trigger_threshold: float = 0.35
@export var flip_cooldown: float = 0.18

var vel: Vector2 = Vector2.ZERO

# Flag de orientação (não é reflexão em X/Y!)
# flipped = visual; facing_sign = física (+1 normal, -1 invertido)
var flipped: bool = false
var facing_sign: float = 1.0

@onready var ship_sprite: Sprite2D = $Ship

var _flip_lock: bool = false


func _ready() -> void:
	# fallback: se você não setar tex_side no Inspector, usa a textura atual do Ship
	if tex_side == null:
		tex_side = ship_sprite.texture

	var pads: PackedInt32Array = Input.get_connected_joypads()
	print("Joypads conectados: ", pads)
	for pid: int in pads:
		print("ID:", pid, " Nome:", Input.get_joy_name(pid))


func _physics_process(delta: float) -> void:
	# Stick esquerdo (para alta velocidade / fallback)
	var stick: Vector2 = _get_stick_left()
	var lx: float = stick.x

	# deadzone pro stick X (evita drift)
	if abs(lx) < 0.15:
		lx = 0.0

	var speed: float = vel.length()
	var low_speed: bool = speed < low_speed_threshold

	# ---------- ROTAÇÃO ----------
	# D-pad (digital) gira contínuo enquanto segurar.
	# IMPORTANTE: multiplica por facing_sign para manter sensação consistente após flip.
	var turn_dpad: float = Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	
	if flipped:
		turn_dpad = -turn_dpad
		lx = -lx
		
	if low_speed:
		var turn_src: float = turn_dpad if abs(turn_dpad) > 0.0 else lx
		rotation += turn_src * rotation_speed_low * delta #* facing_sign
	else:
		rotation += lx * rotation_speed * delta #* facing_sign

	# ---------- FLIP (L2/R2) ----------
	_handle_trigger_flips()

	# ---------- MOVIMENTO ----------
	# forward físico usa facing_sign (escala) => inverte direção sem reflexão
	var forward: Vector2 = Vector2.RIGHT.rotated(rotation) * facing_sign

	# Aceleração para frente (button_0)
	var thrust: float = Input.get_action_strength("button_0") # 0..1
	if thrust > 0.0:
		vel += forward * accel * thrust * delta

	# Subir/Descer (L1 sobe, R1 desce) no eixo Y da tela
	var up_down: float = Input.get_action_strength("button_R1") - Input.get_action_strength("button_L1")
	if up_down != 0.0:
		var strafe_accel: float = accel * strafe_multiplier
		vel += Vector2(0.0, 1.0) * strafe_accel * up_down * delta

	# ---------- VISUAL: troca para sprite "frente" ao subir/descer ----------
	_update_visual_front(up_down)

	# limite velocidade
	if vel.length() > max_speed:
		vel = vel.normalized() * max_speed

	# inércia
	vel = vel.move_toward(Vector2.ZERO, damp * delta)

	velocity = vel
	move_and_slide()

	# quique (opcional)
	if bounce_factor > 0.0 and get_slide_collision_count() > 0:
		vel = vel.bounce(get_last_slide_collision().get_normal()) * bounce_factor

	_screen_wrap(wrap_margin)


func _update_visual_front(up_down: float) -> void:
	# Se não houver tex_front configurada, não faz nada
	if tex_front == null:
		return

	# Se estiver subindo ou descendo, mostra nave de frente
	if abs(up_down) > 0.01:
		if ship_sprite.texture != tex_front:
			ship_sprite.texture = tex_front
	else:
		if ship_sprite.texture != tex_side and tex_side != null:
			ship_sprite.texture = tex_side


func _get_stick_left() -> Vector2:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	var v: Vector2 = Vector2.ZERO

	if not pads.is_empty():
		var id: int = pads[0]
		v.x = float(Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		v.y = float(Input.get_joy_axis(id, JOY_AXIS_LEFT_X))
	else:
		# fallback teclado (se você criar essas ações)
		#v.x = Input.get_action_strength("right") - Input.get_action_strength("left")
		#v.y = Input.get_action_strength("down") - Input.get_action_strength("up")
		v.x = Input.get_action_strength("down") - Input.get_action_strength("up")
		v.y = Input.get_action_strength("right") - Input.get_action_strength("left")

	# deadzone
	if v.length() < deadzone:
		return Vector2.ZERO

	if v.length() > 1.0:
		v = v.normalized()

	return v


func _handle_trigger_flips() -> void:
	var l2: float = Input.get_action_strength("flip_l2")
	var r2: float = Input.get_action_strength("flip_r2")

	if _flip_lock:
		return

	# qualquer trigger aciona a manobra (um por cooldown)
	if l2 > trigger_threshold or r2 > trigger_threshold:
		_apply_flip_maneuver()


func _apply_flip_maneuver() -> void:
	# trava rápida pra não flipar a cada frame segurando gatilho
	_flip_lock = true
	get_tree().create_timer(flip_cooldown).timeout.connect(func(): _flip_lock = false)

	# Aqui fazemos uma "manobra" de inverter direção:
	# - Visual: flip_h
	# - Física: facing_sign muda, mantendo giro consistente
	flipped = not flipped
	ship_sprite.flip_h = flipped
	facing_sign = -1.0 if flipped else 1.0

	# flip_v fica como efeito visual opcional (descomente se quiser usar outro botão)
	# ship_sprite.flip_v = false


func _screen_wrap(margin: float = 0.0) -> void:
	var rect: Rect2 = get_viewport().get_visible_rect()
	var min_x: float = rect.position.x - margin
	var max_x: float = rect.position.x + rect.size.x + margin
	var min_y: float = rect.position.y - margin
	var max_y: float = rect.position.y + rect.size.y + margin

	var p: Vector2 = global_position

	if p.x < min_x:
		p.x = max_x
	elif p.x > max_x:
		p.x = min_x

	if p.y < min_y:
		p.y = max_y
	elif p.y > max_y:
		p.y = min_y

	global_position = p
