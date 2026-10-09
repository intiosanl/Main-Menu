-- Connected Discord-GitHub

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

-- Every tunable
local CONFIG = {
	TITLE_TEXT = "MENU\nSHOWCASE",
	TITLE_PART_SIZE = Vector3.new(10, 4, 0.01),
	TITLE_STROKE_TRANSPARENCY = 0.3,

	FOV = { DEFAULT = 90, MENU = 65, HOVER = 60, GAME = 70 },

	CAMERA_DISTANCE = { MIN = 11, MAX = 13 },
	CAMERA_HEIGHT = { MIN = 0.4, MAX = 1.1 },
	CAMERA_ANGLE_DEG = { MIN = 20, MAX = 50 },
	SCREEN_OFFSET = { MIN = 2.5, MAX = 3.5 },
	LOOK_HEIGHT = 2, -- aim at roughly chest height instead of the feet

	WALL_DEPTH_OFFSET = -1,
	TITLE_Y_OFFSET = { MIN = 1.9, MAX = 2.8 },
	TITLE_X_SHIFT = { MIN = 2.7, MAX = 3.7 },

	UI_SCALE = { MIN = 0.90, MAX = 1.25 },
	HOVER_BUTTON_SCALE = 1.2,

	-- Higher = snappier (Multiplied by deltaTime so the feel is fps independent)
	LOOK_SMOOTHING = 5,
	UI_SCALE_SMOOTHING = 4,
	MOUSE_LOOK_STRENGTH = Vector2.new(1.0, 0.7),

	-- Sine ways on each axis that don't repeat, so the camera feels handheld
	SWAY = {
		POS_AMPLITUDE = Vector3.new(0.35, 0.22, 0.18),
		POS_SPEED = Vector3.new(0.6, 0.5, 0.38),
		POS_PHASE = Vector3.new(0, 1.3, 2.7),
		ROT_AMPLITUDE_DEG = Vector3.new(0.9, 1.6, 0.5), -- pitch, yaw, roll
		ROT_SPEED = Vector3.new(0.37, 0.45, 0.29),
		ROT_PHASE = Vector3.new(2.4, 0.6, 4.0),
	},

	-- Time of day windows that look good for a cinematic shot
	CLOCK_WINDOWS = { { 5.8, 7.2 }, { 12.0, 14.0 }, { 17.5, 19.0 }, { 21.5, 23.5 } },

	DOF = { FAR_INTENSITY = 0.75, NEAR_INTENSITY = 0, IN_FOCUS_RADIUS = 4 },
	BLOOM = { INTENSITY = 0.4, SIZE = 24, THRESHOLD = 1.6 },
	GRADE = { CONTRAST = 0.08, SATURATION = -0.05, TINT = Color3.fromRGB(235, 240, 255) },
	RIM_LIGHT = { COLOR = Color3.fromRGB(180, 210, 255), BRIGHTNESS = 1.2, RANGE = 8 },

	INTRO = {
		CAMERA_TWEEN = 1.3,
		BAR_TWEEN = 1,
		TITLE_TWEEN = 2,
		BUTTON_STAGGER = 0.2,
		BUTTON_TWEEN_BASE = 0.7,
		BUTTON_TWEEN_STEP = 0.1,
		BUTTONS_START_SIZE = UDim2.fromOffset(50, 25),
		BUTTONS_END_SIZE = UDim2.fromOffset(135, 150),
	},

	BARS = {
		TOP_HIDDEN = UDim2.fromScale(0.5, -0.13),
		TOP_HOVER = UDim2.fromScale(0.5, -0.07),
		BOTTOM_HIDDEN = UDim2.fromScale(0.5, 1.13),
		BOTTOM_HOVER = UDim2.fromScale(0.5, 1.07),
	},

	WIPE = { DURATION = 1, ROTATION = 40, SIZE = UDim2.fromScale(3, 3), HOLD = 0.4 },
	LOADED_FLAG_TIMEOUT = 5,
	RENDER_STEP_NAME = "MenuCamera",
}

local HOVER_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)


-- Helpers

local function create(className, properties, parent)
	local instance = Instance.new(className)
	for name, value in properties do
		instance[name] = value
	end
	instance.Parent = parent
	return instance
end

-- If a UI scale unintentionally doesn't exist when it's needed, create one so the code doesn't fail
local function getUIScale(guiObject)
	return guiObject:FindFirstChildOfClass("UIScale") or create("UIScale", {}, guiObject)
end

local rng = Random.new()

local function randomRange(range)
	return rng:NextNumber(range.MIN, range.MAX)
end

-- Waiting for ChildAdded once avoids polling without requiring the full list to be present
local function getChildrenWhenAvailable(folder)
	local children = folder:GetChildren()
	if #children == 0 then
		warn(`{folder.Name} is empty, waiting for its first child`)
		folder.ChildAdded:Wait()
		children = folder:GetChildren()
	end
	return children
end

local function oscillate(time, speed, phase, amplitude)
	return math.sin(time * speed + phase) * amplitude
end

-- References

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local menuGui = playerGui:WaitForChild("MenuGui")
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")
local hrp = character:WaitForChild("HumanoidRootPart")

local bars = menuGui:WaitForChild("Bars")
local topBar = bars:WaitForChild("TopBar")
local bottomBar = bars:WaitForChild("BottomBar")
local buttonsFrame = menuGui:WaitForChild("Buttons")
local buttonsFrameScale = getUIScale(buttonsFrame)

local assets = ReplicatedStorage:WaitForChild("Assets")
local hoverSound = assets:WaitForChild("Sounds"):WaitForChild("Hover")
local clickSound = assets.Sounds:WaitForChild("Click")

local camera = Workspace.CurrentCamera
local originalClockTime = Lighting.ClockTime
local isLoadedValue = player:WaitForChild("IsLoaded", CONFIG.LOADED_FLAG_TIMEOUT)

local menuButtons = {}
for _, child in buttonsFrame:GetChildren() do
	if child:IsA("TextButton") then
		table.insert(menuButtons, child)
	end
end

local state = {
	inMenu = true,
	isTransitioning = false, -- guards hover/click so nothing fires mid transition
}

-- Everything the menu adds to the world goes in here, so cleanup is one loop and nothing leaks
local spawnedInstances = {}
local function track(instance)
	table.insert(spawnedInstances, instance)
	return instance
end

-- Scene selection

local animations = getChildrenWhenAvailable(assets:WaitForChild("Animations"))
local menuPOIs = getChildrenWhenAvailable(Workspace:WaitForChild("MenuPOIs"))

local selectedPOI = menuPOIs[rng:NextInteger(1, #menuPOIs)]
local poiCFrame = selectedPOI:GetPivot()

-- Which side the character is placed on decides which side the buttons sit on (and the title goes opposite)
local sideMultiplier = rng:NextInteger(0, 1) == 0 and -1 or 1
local screenOffset = randomRange(CONFIG.SCREEN_OFFSET) * sideMultiplier
local cameraDistance = rng:NextInteger(CONFIG.CAMERA_DISTANCE.MIN, CONFIG.CAMERA_DISTANCE.MAX)

local baseCamCFrame = CFrame.identity
local menuAnimationTrack

-- 3D title

-- The title is on an invisible part with a SurfaceGui instead of a ScreenGui, so it gets a 3d look
local titlePart = track(create("Part", {
	Name = "MenuTitle",
	Size = CONFIG.TITLE_PART_SIZE,
	Anchored = true,
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
	Transparency = 1,
}))

local titleSurface = create("SurfaceGui", {
	Face = Enum.NormalId.Front,
	SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
	CanvasSize = Vector2.new(1000, 400),
	LightInfluence = 0, -- keep the text readable
}, titlePart)

local titleLabel = create("TextLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	FontFace = Font.fromEnum(Enum.Font.GothamBlack),
	Text = CONFIG.TITLE_TEXT,
	TextTransparency = 1, -- starts hidden, faded in by revealMenu
	TextScaled = true,
	RichText = true,
	TextColor3 = selectedPOI:IsA("BasePart") and selectedPOI.Color or Color3.new(1, 1, 1),
}, titleSurface)

local titleStroke = create("UIStroke", {
	Thickness = 4,
	Color = Color3.new(1, 1, 1),
	Transparency = 1,
}, titleLabel)

-- Hover tweens

local function makeHoverTween(target, goal)
	return TweenService:Create(target, HOVER_TWEEN_INFO, goal)
end

local sharedHoverTweens = {
	[true] = {
		makeHoverTween(camera, { FieldOfView = CONFIG.FOV.HOVER }),
		makeHoverTween(topBar, { Position = CONFIG.BARS.TOP_HOVER }),
		makeHoverTween(bottomBar, { Position = CONFIG.BARS.BOTTOM_HOVER }),
	},
	[false] = {
		makeHoverTween(camera, { FieldOfView = CONFIG.FOV.MENU }),
		makeHoverTween(topBar, { Position = CONFIG.BARS.TOP_HIDDEN }),
		makeHoverTween(bottomBar, { Position = CONFIG.BARS.BOTTOM_HIDDEN }),
	},
}

local buttonHoverTweens = {}
for _, button in menuButtons do
	local uiScale = getUIScale(button)
	uiScale.Scale = 0 -- hidden until the reveal scales it up
	buttonHoverTweens[button] = {
		[true] = makeHoverTween(uiScale, { Scale = CONFIG.HOVER_BUTTON_SCALE }),
		[false] = makeHoverTween(uiScale, { Scale = 1 }),
	}
end

local function onButtonHover(button, isHovering)
	if state.isTransitioning then
		return
	end
	for _, tween in sharedHoverTweens[isHovering] do
		tween:Play()
	end
	buttonHoverTweens[button][isHovering]:Play()
end

-- Reveal

camera.FieldOfView = CONFIG.FOV.DEFAULT
buttonsFrame.Size = CONFIG.INTRO.BUTTONS_START_SIZE

local function revealMenu()
	local intro = CONFIG.INTRO
	local sine = TweenInfo.new(intro.TITLE_TWEEN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

	TweenService:Create(camera, TweenInfo.new(intro.CAMERA_TWEEN, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		FieldOfView = CONFIG.FOV.MENU,
	}):Play()
	TweenService:Create(topBar, TweenInfo.new(intro.BAR_TWEEN), { Position = CONFIG.BARS.TOP_HIDDEN }):Play()
	TweenService:Create(bottomBar, TweenInfo.new(intro.BAR_TWEEN), { Position = CONFIG.BARS.BOTTOM_HIDDEN }):Play()
	TweenService:Create(buttonsFrame, TweenInfo.new(intro.BAR_TWEEN, Enum.EasingStyle.Bounce), {
		Size = intro.BUTTONS_END_SIZE,
	}):Play()
	TweenService:Create(titleLabel, sine, { TextTransparency = 0 }):Play()
	TweenService:Create(titleStroke, sine, { Transparency = CONFIG.TITLE_STROKE_TRANSPARENCY }):Play()

	-- Staggering the buttons
	for index, button in menuButtons do
		local order = index - 1
		task.delay(order * intro.BUTTON_STAGGER, function()
			TweenService:Create(
				getUIScale(button),
				TweenInfo.new(intro.BUTTON_TWEEN_BASE + order * intro.BUTTON_TWEEN_STEP),
				{ Scale = 1 }
			):Play()
		end)
	end

	menuGui.Enabled = true
end

-- The menu must not reveal until the server says the game has loaded
if not isLoadedValue then
	warn("[MainMenu] IsLoaded flag never appeared, revealing anyway")
	revealMenu()
elseif isLoadedValue.Value then
	revealMenu()
else
	local connection
	connection = isLoadedValue:GetPropertyChangedSignal("Value"):Connect(function()
		if isLoadedValue.Value then
			connection:Disconnect()
			revealMenu()
		end
	end)
end

-- Scene setup

local function setupMenu()
	-- The default Animate script keeps starting its own idle on top of ours (we don't want that, so we disable it)
	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = true
	end

	local idleAnimation = animations[rng:NextInteger(1, #animations)]
	menuAnimationTrack = animator:LoadAnimation(idleAnimation)
	menuAnimationTrack.Looped = true
	menuAnimationTrack.Priority = Enum.AnimationPriority.Action4 -- safeguard
	menuAnimationTrack:Play()

	hrp.CFrame = poiCFrame
	hrp.Anchored = true

	-- Orbit the camera around the POI by a random yaw, then pull it back along the local Z axis
	-- Randomizing yaw, height and distance gives a different framing on every join
	local angleDeg = rng:NextInteger(CONFIG.CAMERA_ANGLE_DEG.MIN, CONFIG.CAMERA_ANGLE_DEG.MAX)
	local yaw = math.rad(rng:NextInteger(0, 1) == 0 and angleDeg or -angleDeg)
	baseCamCFrame = poiCFrame * CFrame.Angles(0, yaw, 0) * CFrame.new(0, randomRange(CONFIG.CAMERA_HEIGHT), -cameraDistance)

	-- The wall's LookVector can point either toward or away from the character depending on how it was modelled
	-- The dot product against the vector to the character tells us which, and we flip 180 degrees if needed so the title text always faces the player
	local wall = selectedPOI:FindFirstChild("Wall") or selectedPOI
	local wallCFrame = wall:IsA("BasePart") and wall.CFrame or poiCFrame
	local wallRotation = wallCFrame.Rotation

	if wallCFrame.LookVector:Dot(hrp.Position - wallCFrame.Position) < 0 then
		wallRotation *= CFrame.Angles(0, math.pi, 0)
	end

	local forwardNormal = wallRotation.LookVector
	local wallRight = wallRotation.RightVector

	-- Title height is relative to the head, not the world
	local headY = (character:FindFirstChild("Head") or hrp).Position.Y
	local targetY = headY + randomRange(CONFIG.TITLE_Y_OFFSET)

	-- The title goes on the opposite side of the buttons so they don't look overlapped
	-- we compare the wall's right vector with the camera's right vector; if they point opposite ways, the shift must be negated
	local titleOnLeft = screenOffset < 0
	local camRightSign = wallRight:Dot(baseCamCFrame.RightVector) >= 0 and 1 or -1
	local screenSideSign = titleOnLeft and -1 or 1
	local titleXShift = wallRight * (screenSideSign * camRightSign * randomRange(CONFIG.TITLE_X_SHIFT))

	-- Text aligns toward the screen edge it sits near so it hugs the frame instead of floating inward
	titleLabel.TextXAlignment = titleOnLeft and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left

	local basePos = wallCFrame.Position + forwardNormal * CONFIG.WALL_DEPTH_OFFSET + titleXShift
	titlePart.CFrame = CFrame.new(basePos.X, targetY, basePos.Z) * wallRotation
	titlePart.Parent = Workspace

	local window = CONFIG.CLOCK_WINDOWS[rng:NextInteger(1, #CONFIG.CLOCK_WINDOWS)]
	Lighting.ClockTime = rng:NextNumber(window[1], window[2])

	-- Post processing

	-- These effects only exist during the menu (tracked for cleanup), so gameplay visuals are untouched
	-- FocusDistance is updated every frame in the camera step so the character stays sharp as the camera sways.
	track(create("DepthOfFieldEffect", {
		Name = "MenuAutofocus",
		FarIntensity = CONFIG.DOF.FAR_INTENSITY,
		NearIntensity = CONFIG.DOF.NEAR_INTENSITY,
		InFocusRadius = CONFIG.DOF.IN_FOCUS_RADIUS,
	}, Lighting))

	track(create("BloomEffect", {
		Name = "MenuBloom",
		Intensity = CONFIG.BLOOM.INTENSITY,
		Size = CONFIG.BLOOM.SIZE,
		Threshold = CONFIG.BLOOM.THRESHOLD, -- high threshold, only the very bright highlights glow
	}, Lighting))

	track(create("ColorCorrectionEffect", {
		Name = "MenuColorGrade",
		Contrast = CONFIG.GRADE.CONTRAST,
		Saturation = CONFIG.GRADE.SATURATION,
		TintColor = CONFIG.GRADE.TINT,
	}, Lighting))

	track(create("PointLight", {
		Color = CONFIG.RIM_LIGHT.COLOR,
		Brightness = CONFIG.RIM_LIGHT.BRIGHTNESS,
		Range = CONFIG.RIM_LIGHT.RANGE,
	}, hrp))

	-- Scriptable hands the CFrame entirely to us, so the default camera wouldn't fight the sway every frame
	camera.CameraType = Enum.CameraType.Scriptable
end

setupMenu()

local dofEffect = Lighting:FindFirstChild("MenuAutofocus")

-- Camera and UI projection

local currentX, currentY = 0, 0
local currentButtonScale = 1.1

-- Makes it so the 
local function worldToGui(position)
	if menuGui.IgnoreGuiInset then
		return camera:WorldToViewportPoint(position) -- ignores the top inset
	end
	return camera:WorldToScreenPoint(position) -- subtracts the top inset
end

local function updateMenuCamera(deltaTime)
	-- Touch and gamepads don't have a cursor so only the ambient sway is displayed
	local targetX, targetY = 0, 0
	if UserInputService.MouseEnabled then
		local mousePos = UserInputService:GetMouseLocation()
		local viewport = camera.ViewportSize
		-- Normalized to -1..1 and inverted so the camera drifts away from the cursor (a parallax feel)
		targetX = -((mousePos.X / viewport.X) * 2 - 1)
		targetY = -((mousePos.Y / viewport.Y) * 2 - 1)
	end

	-- Smoothing scaled by deltaTime, same easing on any fps
	local lookAlpha = math.min(deltaTime * CONFIG.LOOK_SMOOTHING, 1)
	currentX += (targetX - currentX) * lookAlpha
	currentY += (targetY - currentY) * lookAlpha

	-- Offsets are in the camera's frame (a bit right, a bit up) then rotated into world space
	local lookOffset = baseCamCFrame:VectorToWorldSpace(
		Vector3.new(currentX * CONFIG.MOUSE_LOOK_STRENGTH.X, currentY * CONFIG.MOUSE_LOOK_STRENGTH.Y, 0)
	)
	-- Aiming past the character pushes them off center, leaving room for the buttons on the other side
	local framingOffset = baseCamCFrame.RightVector * -screenOffset
	local targetPos = poiCFrame.Position + Vector3.new(0, CONFIG.LOOK_HEIGHT, 0) + lookOffset + framingOffset

	local sway = CONFIG.SWAY
	local now = os.clock()
	local swayOffset = baseCamCFrame:VectorToWorldSpace(Vector3.new(
		oscillate(now, sway.POS_SPEED.X, sway.POS_PHASE.X, sway.POS_AMPLITUDE.X),
		oscillate(now, sway.POS_SPEED.Y, sway.POS_PHASE.Y, sway.POS_AMPLITUDE.Y),
		oscillate(now, sway.POS_SPEED.Z, sway.POS_PHASE.Z, sway.POS_AMPLITUDE.Z)
		))
	local swayPitch = math.rad(oscillate(now, sway.ROT_SPEED.X, sway.ROT_PHASE.X, sway.ROT_AMPLITUDE_DEG.X))
	local swayYaw = math.rad(oscillate(now, sway.ROT_SPEED.Y, sway.ROT_PHASE.Y, sway.ROT_AMPLITUDE_DEG.Y))
	local swayRoll = math.rad(oscillate(now, sway.ROT_SPEED.Z, sway.ROT_PHASE.Z, sway.ROT_AMPLITUDE_DEG.Z))

	camera.CFrame = CFrame.lookAt(baseCamCFrame.Position + swayOffset, targetPos)
		* CFrame.Angles(swayPitch, swayYaw, swayRoll)

	-- Buttons scale with how far the camera is from the framing target so they keep a consistent size next to the character
	local liveDistance = (camera.CFrame.Position - targetPos).Magnitude
	local targetButtonScale = math.clamp(cameraDistance / liveDistance, CONFIG.UI_SCALE.MIN, CONFIG.UI_SCALE.MAX)
	
	currentButtonScale += (targetButtonScale - currentButtonScale) * math.min(deltaTime * CONFIG.UI_SCALE_SMOOTHING, 1)
	buttonsFrameScale.Scale = currentButtonScale

	if dofEffect then
		-- Focus on the character (not the title or background) so they stay sharp while things further out blurs
		dofEffect.FocusDistance = (camera.CFrame.Position - hrp.Position).Magnitude
	end

	-- The buttons are 2D but need to stay on the 3d character, so their position is reprojected every frame
	-- (a fixed UDim2 would drift away as the camera sways)
	local uiWorldPos = hrp.Position + Vector3.new(0, CONFIG.LOOK_HEIGHT, 0) + baseCamCFrame.RightVector * -screenOffset * 2
	local screenPos, onScreen = worldToGui(uiWorldPos)
	buttonsFrame.Visible = onScreen -- hidden when the point is behind the camera
	if onScreen then
		buttonsFrame.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
	end
end

-- Priority just above camera means we run after roblox's own camera update, so nothing overwrites our CFrame
-- BindToRenderStep also lets us unbind it by name later
RunService:BindToRenderStep(CONFIG.RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, updateMenuCamera)

-- Play transition and cleanup

local function startPlayTransition()
	state.isTransitioning = true

	-- Interactable = false blocks mouse, touch and gamepad in one flag, so a second click can't start the transition twice
	for _, button in menuButtons do
		button.Interactable = false
	end

	-- The bars grow past the screen edges while rotating, hiding the hard cut back to gameplay
	local wipeInfo = TweenInfo.new(CONFIG.WIPE.DURATION, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	local wipeGoal = { Rotation = CONFIG.WIPE.ROTATION, Size = CONFIG.WIPE.SIZE }
	TweenService:Create(topBar, wipeInfo, wipeGoal):Play()
	
	local bottomTween = TweenService:Create(bottomBar, wipeInfo, wipeGoal)
	bottomTween:Play()
	bottomTween.Completed:Wait()
	
	task.wait(CONFIG.WIPE.HOLD) -- short beat on the covered screen so the cut isn't noticeable
	
	-- Clean up
	state.inMenu = false
	RunService:UnbindFromRenderStep(CONFIG.RENDER_STEP_NAME)
	buttonsFrame:Destroy()

	for _, instance in spawnedInstances do
		instance:Destroy()
	end
	table.clear(spawnedInstances)
	dofEffect = nil

	if menuAnimationTrack then
		menuAnimationTrack:Stop(0.3)
	end

	-- The camera is handed back and the character unanchored while the bars still cover the screen, so the player never sees a snap
	camera.CameraType = Enum.CameraType.Custom
	hrp.Anchored = false

	local animateScript = character:FindFirstChild("Animate")
	if animateScript then
		animateScript.Disabled = false
	end

	local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(camera, fadeInfo, { FieldOfView = CONFIG.FOV.GAME }):Play()
	TweenService:Create(Lighting, fadeInfo, { ClockTime = originalClockTime }):Play()
	TweenService:Create(topBar, fadeInfo, { BackgroundTransparency = 1 }):Play()
	
	local finalFade = TweenService:Create(bottomBar, fadeInfo, { BackgroundTransparency = 1 })
	finalFade:Play()
	finalFade.Completed:Wait()

	menuGui:Destroy() -- only after the fade, otherwise the bars would vanish mid tween
end

-- Button wiring

-- Each button maps to one handler, so adding a button is just one table entry
-- Names must match the instances in studio exactly else the button does nothing
local buttonActions = {
	PlayButton = startPlayTransition,
	
	UpdatesButton = function()
		print("Updates button clicked")
	end,
	
	ShopButton = function()
		print("Shop button clicked")
	end,
}

for _, button in menuButtons do
	button.MouseEnter:Connect(function()
		onButtonHover(button, true)
		if not state.isTransitioning then
			hoverSound:Play()
		end
	end)

	button.MouseLeave:Connect(function()
		onButtonHover(button, false)
	end)

	-- Activated works for mouse, touch and gamepad
	button.Activated:Connect(function()
		if state.isTransitioning then
			return
		end
		clickSound:Play()

		local action = buttonActions[button.Name]
		if action then
			action()
		else
			warn(`[MainMenu] no action registered for button "{button.Name}"`)
		end
	end)
end
