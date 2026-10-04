-- Connected Discord-GitHub

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

-- Config
local CONFIG = {
	TITLE_TEXT = "MENU\nSHOWCASE",
	TITLE_PART_SIZE = Vector3.new(10, 4, 0.01),

	-- Camera FOV
	DEFAULT_FOV = 90,
	MENU_FOV = 65,
	HOVER_FOV = 60,
	GAME_FOV = 70,

	-- Distance and framing
	CAMERA_DISTANCE = { MIN = 11, MAX = 13 },
	SCREEN_OFFSET = { MIN = 2.5, MAX = 3.5 },

	-- Header title offsets
	WALL_DEPTH_OFFSET = -1,
	TITLE_Y_OFFSET = { MIN = 1.9, MAX = 2.8 },
	TITLE_X_SHIFT = { MIN = 2.7, MAX = 3.7 },

	-- UI scale
	UI_SCALE_MIN = 0.90,
	UI_SCALE_MAX = 1.25,
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") 
local menuGui = playerGui:WaitForChild("MenuGui") -- Main menu GUI
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local hrp = character:WaitForChild("HumanoidRootPart")
local playerScripts = player:WaitForChild("PlayerScripts")

-- UI references
local topBar = menuGui.Bars:WaitForChild("TopBar") -- Top cinematic bar
local bottomBar = menuGui.Bars:WaitForChild("BottomBar") -- Bottom cinematic bar
local buttonsFrame = menuGui:WaitForChild("Buttons") -- Buttons container
local buttonsFrameScale = buttonsFrame:FindFirstChild("UIScale") -- Button scale modifier
local playButton = buttonsFrame:WaitForChild("PlayButton") -- Play button
local settingsButton = buttonsFrame:WaitForChild("UpdatesButton") -- Updates button
local updatesButton = buttonsFrame:WaitForChild("ShopButton") -- Shop button

-- Header title initialization
local titlePart = Instance.new("Part") -- Carrier part for 3D title
titlePart.Name = "MenuTitle"
titlePart.Size = CONFIG.TITLE_PART_SIZE
titlePart.Anchored = true
titlePart.CanCollide = false
titlePart.CanQuery = false
titlePart.CastShadow = false
titlePart.Transparency = 1

local titleSurface = Instance.new("SurfaceGui")
titleSurface.Face = Enum.NormalId.Front
titleSurface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
titleSurface.CanvasSize = Vector2.new(1000, 400)
titleSurface.LightInfluence = 0
titleSurface.Parent = titlePart

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.fromScale(1, 1)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.Text = CONFIG.TITLE_TEXT
titleLabel.TextTransparency = 1
titleLabel.TextScaled = true
titleLabel.RichText = true 
titleLabel.Parent = titleSurface

local titleStroke = Instance.new("UIStroke")
titleStroke.Thickness = 4
titleStroke.Color = Color3.fromRGB(255, 255, 255)
titleStroke.Transparency = 1
titleStroke.Parent = titleLabel

local camera = Workspace.CurrentCamera
camera.FieldOfView = CONFIG.DEFAULT_FOV
local originalClockTime = Lighting.ClockTime
local isLoadedVal = player:WaitForChild("IsLoaded", 5) -- Loading state flag

local IN_MENU = true
local IS_TRANSITIONING = false

local menuAnimationTrack -- Active animation track
local dofEffect -- Depth of field blur
local bloomEffect -- Bloom glow effect
local colorGradeEffect -- Color correction effect
local rimLight -- Character rim light

local soundsFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Sounds")
local hoverSound = soundsFolder:WaitForChild("Hover") -- Hover sound
local clickSound = soundsFolder:WaitForChild("Click") -- Click sound

local animFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")
local animations = animFolder:GetChildren() -- Idle animations table

if #animations == 0 then
	warn("menu animations folder empty - waiting for animations to load")
	animFolder.ChildAdded:Wait() -- Wait for assets to load
	animations = animFolder:GetChildren()
end

local menuPOIsFolder = Workspace:WaitForChild("MenuPOIs")
local menuPOIs = menuPOIsFolder:GetChildren() -- Menu scene POIs

if #menuPOIs == 0 then
	warn("menu pois folder empty - waiting for pois to load...")
	menuPOIsFolder.ChildAdded:Wait() -- Wait for POIs to load
	menuPOIs = menuPOIsFolder:GetChildren()
end

local selectedPOI = menuPOIs[math.random(1, #menuPOIs)] -- Picks random scene POI
local baseCamCFrame = CFrame.identity

titleLabel.TextColor3 = selectedPOI.Color -- Matches title color to POI

local rng = Random.new() -- Random number generator
local sideMultiplier = rng:NextInteger(0, 1) == 0 and -1 or 1 -- Randomizes left or right side
local screenOffset = rng:NextNumber(CONFIG.SCREEN_OFFSET.MIN, CONFIG.SCREEN_OFFSET.MAX) * sideMultiplier
local cameraDistance = rng:NextInteger(CONFIG.CAMERA_DISTANCE.MIN, CONFIG.CAMERA_DISTANCE.MAX)

buttonsFrame.Size = UDim2.new(0, 50, 0, 25)

-- Hide button for intro animation
playButton:FindFirstChild("UIScale").Scale = 0
settingsButton:FindFirstChild("UIScale").Scale = 0
updatesButton:FindFirstChild("UIScale").Scale = 0

-- Reveal menu
local function revealMenu()
	TweenService:Create(camera, TweenInfo.new(1.3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		FieldOfView = CONFIG.MENU_FOV -- Tweens camera FOV
	}):Play()
	TweenService:Create(topBar, TweenInfo.new(1), {Position = UDim2.new(0.5, 0, -0.13, 0)}):Play() -- Top bar tween
	TweenService:Create(bottomBar, TweenInfo.new(1), {Position = UDim2.new(0.5, 0, 1.13, 0)}):Play() -- Bottom bar tween
	TweenService:Create(buttonsFrame, TweenInfo.new(1, Enum.EasingStyle.Bounce), {Size = UDim2.new(0, 135, 0, 150)}):Play() -- Button container bounce
	TweenService:Create(titleLabel, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {TextTransparency = 0}):Play() -- Fades in title text
	TweenService:Create(titleStroke, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Transparency = 0.3}):Play() -- Fades in text outline

	local buttonIndex = 0
	for _, child in ipairs(buttonsFrame:GetChildren()) do
		if child:IsA("TextButton") then
			local uiScale = child:FindFirstChild("UIScale") -- Gets button scale
			if uiScale then
				task.delay(buttonIndex * 0.2, function() -- Staggers button entry
					TweenService:Create(uiScale, TweenInfo.new(0.7 + (buttonIndex * 0.1)), {Scale = 1}):Play() -- Scales button up
				end)
				buttonIndex += 1
			end
		end
	end

	menuGui.Enabled = true -- Shows menu GUI
end

if isLoadedVal then
	if isLoadedVal.Value then
		revealMenu()
	else
		local isLoadedConnection
		isLoadedConnection = isLoadedVal:GetPropertyChangedSignal("Value"):Connect(function()
			if isLoadedVal.Value then
				if isLoadedConnection then
					isLoadedConnection:Disconnect() -- Disconnects listener to prevent memory leaks
					isLoadedConnection = nil
				end
				revealMenu()
			end
		end)
	end
else
	warn("[MainMenu] IsLoaded never appeared - fallback reveal")
	revealMenu()
end

-- Button hover effect
local function onButtonHover(button, isHovering)
	if IS_TRANSITIONING then return end

	local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local targetFOV = isHovering and CONFIG.HOVER_FOV or CONFIG.MENU_FOV -- Camera zoom on hover
	TweenService:Create(camera, tweenInfo, { FieldOfView = targetFOV }):Play()

	local uiScale = button:FindFirstChild("UIScale")
	if uiScale then
		local targetScale = isHovering and 1.2 or 1 -- Scale button on hover
		TweenService:Create(uiScale, tweenInfo, { Scale = targetScale }):Play()
	end

	local targetTopPos = isHovering and UDim2.new(0.5, 0, -0.07, 0) or UDim2.new(0.5, 0, -0.13, 0) -- Top bar hover tween
	local targetBottomPos = isHovering and UDim2.new(0.5, 0, 1.07, 0) or UDim2.new(0.5, 0, 1.13, 0) -- Bottom bar hover tween
	TweenService:Create(topBar, tweenInfo, { Position = targetTopPos }):Play()
	TweenService:Create(bottomBar, tweenInfo, { Position = targetBottomPos }):Play()
end

-- Scene and menu setup
local function setupMenu()	
	if character:FindFirstChild("Animate") then
		character.Animate.Disabled = true -- Disable default animations
	end

	local animator = humanoid:WaitForChild("Animator")
	local selectedAnimation = animations[math.random(1, #animations)]
	menuAnimationTrack = animator:LoadAnimation(selectedAnimation) -- Load idle animation
	menuAnimationTrack.Looped = true
	menuAnimationTrack.Priority = Enum.AnimationPriority.Action4 -- Action priority overrides default animations
	menuAnimationTrack:Play()

	hrp.CFrame = selectedPOI.CFrame -- Position character at POI
	hrp.Anchored = true

	local cameraHeight = rng:NextNumber(0.4, 1.1)
	local angleMagnitude = rng:NextInteger(20, 50)
	local randomAngle = math.rad(rng:NextInteger(0, 1) == 0 and angleMagnitude or -angleMagnitude)

	baseCamCFrame = selectedPOI.CFrame 
		* CFrame.Angles(0, randomAngle, 0) 	
		* CFrame.new(0, cameraHeight, -cameraDistance) -- Offsets camera from POI using CFrame angles and distance

	-- Wall and header title alignment
	local wall = selectedPOI:WaitForChild("Wall", 3) or selectedPOI:FindFirstChild("Wall") or selectedPOI
	local wallCFrame = wall:IsA("BasePart") and wall.CFrame or selectedPOI.CFrame

	-- Face towards player
	local wallRotation = wallCFrame.Rotation
	if wallCFrame.LookVector:Dot(hrp.Position - wallCFrame.Position) < 0 then
		wallRotation *= CFrame.Angles(0, math.pi, 0) -- Dot product checks if wall normal points away from character
	end

	local forwardNormal = wallRotation.LookVector
	local wallRight = wallRotation.RightVector

	-- Y height relative to player head
	local headY = (character:FindFirstChild("Head") or hrp).Position.Y
	local targetY = headY + rng:NextNumber(CONFIG.TITLE_Y_OFFSET.MIN, CONFIG.TITLE_Y_OFFSET.MAX) -- Offsets title Y relative to player head

	-- Shift opposite to buttons
	local buttonsOnRight = screenOffset < 0
	local titleOnLeft = buttonsOnRight

	local camRightSign = (wallRight:Dot(baseCamCFrame.RightVector) >= 0) and 1 or -1 -- Dot product checks if wall faces left or right on screen
	local screenSideSign = titleOnLeft and -1 or 1
	local titleXShift = wallRight * (screenSideSign * camRightSign * rng:NextNumber(CONFIG.TITLE_X_SHIFT.MIN, CONFIG.TITLE_X_SHIFT.MAX)) -- Applies horizontal offset along wall right vector

	titleLabel.TextXAlignment = titleOnLeft and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left -- Align text to screen side

	local basePos = wallCFrame.Position + (forwardNormal * CONFIG.WALL_DEPTH_OFFSET) + titleXShift -- Combines wall position, depth and horizontal shift
	titlePart.CFrame = CFrame.new(basePos.X, targetY, basePos.Z) * wallRotation -- Creates CFrame from position and wall rotation
	titlePart.Parent = Workspace

	local cinematicWindows = {
		{5.8, 7.2},
		{12.0, 14.0},
		{17.5, 19.0},
		{21.5, 23.5}
	}
	local selectedWindow = cinematicWindows[rng:NextInteger(1, #cinematicWindows)]
	Lighting.ClockTime = rng:NextNumber(selectedWindow[1], selectedWindow[2]) -- Set cinematic lighting time

	dofEffect = Instance.new("DepthOfFieldEffect", Lighting) -- Depth of field blur
	dofEffect.Name = "MenuAutofocus"
	dofEffect.FarIntensity = 0.75
	dofEffect.NearIntensity = 0
	dofEffect.InFocusRadius = 4

	bloomEffect = Instance.new("BloomEffect", Lighting) -- Bloom glow effect
	bloomEffect.Name = "MenuBloom"
	bloomEffect.Intensity = 0.4
	bloomEffect.Size = 24
	bloomEffect.Threshold = 1.6

	colorGradeEffect = Instance.new("ColorCorrectionEffect", Lighting) -- Color correction effect
	colorGradeEffect.Name = "MenuColorGrade"
	colorGradeEffect.Contrast = 0.08
	colorGradeEffect.Saturation = -0.05
	colorGradeEffect.TintColor = Color3.fromRGB(235, 240, 255)

	rimLight = Instance.new("PointLight", hrp) -- Character rim light
	rimLight.Color = Color3.fromRGB(180, 210, 255)
	rimLight.Brightness = 1.2
	rimLight.Range = 8

	camera.CameraType = Enum.CameraType.Scriptable -- Scriptable camera mode for custom CFrame control
end

setupMenu()

-- Render loop (camera sway, autofocus and UI projection)
local currentX, currentY = 0, 0
local currentButtonScale = 1.1

local renderConnection
renderConnection = RunService.RenderStepped:Connect(function(deltaTime)
	if not IN_MENU then return end

	local mousePos = UserInputService:GetMouseLocation() -- Mouse cursor position
	local screenSize = camera.ViewportSize

	local targetX = -((mousePos.X / screenSize.X) * 2 - 1) -- Normalizes mouse X to -1 and 1
	local targetY = -((mousePos.Y / screenSize.Y) * 2 - 1) -- Normalizes mouse Y to -1 and 1

	currentX = currentX + (targetX - currentX) * (deltaTime * 5) -- Smooth lerp to mouse X using deltaTime
	currentY = currentY + (targetY - currentY) * (deltaTime * 5) -- Smooth lerp to mouse Y using deltaTime

	local lookOffset = baseCamCFrame:VectorToWorldSpace(Vector3.new(currentX * 1.0, currentY * 0.7, 0)) -- Converts mouse offset from camera space to world space
	local framingOffset = baseCamCFrame.RightVector * -screenOffset
	local targetPos = selectedPOI.CFrame.Position + Vector3.new(0, 2, 0) + lookOffset + framingOffset -- Camera look target

	local currentTime = os.clock()
	local swayX = math.sin(currentTime * 0.6) * 0.35 -- Sine wave oscillation for horizontal sway
	local swayY = math.sin(currentTime * 0.5 + 1.3) * 0.22 -- Sine wave oscillation for vertical sway
	local swayZ = math.sin(currentTime * 0.38 + 2.7) * 0.18 -- Sine wave oscillation for depth sway
	local swayOffset = baseCamCFrame:VectorToWorldSpace(Vector3.new(swayX, swayY, swayZ)) -- Converts sway offset to world space

	local swayYaw = math.rad(math.sin(currentTime * 0.45 + 0.6) * 1.6)
	local swayPitch = math.rad(math.sin(currentTime * 0.37 + 2.4) * 0.9)
	local swayRoll = math.rad(math.sin(currentTime * 0.29 + 4.0) * 0.5)

	camera.CFrame = CFrame.lookAt(baseCamCFrame.Position + swayOffset, targetPos)
		* CFrame.Angles(swayPitch, swayYaw, swayRoll) -- CFrame.lookAt points camera to target with sway angles

	local liveDistance = (camera.CFrame.Position - targetPos).Magnitude -- Magnitude calculates distance to target
	local targetButtonScale = math.clamp(cameraDistance / liveDistance, CONFIG.UI_SCALE_MIN, CONFIG.UI_SCALE_MAX) -- Clamps UI scale based on camera distance
	currentButtonScale = currentButtonScale + (targetButtonScale - currentButtonScale) * (deltaTime * 4)
	buttonsFrameScale.Scale = currentButtonScale

	if dofEffect then
		dofEffect.FocusDistance = (camera.CFrame.Position - hrp.Position).Magnitude -- Sets blur focus distance to character using magnitude
	end

	local uiWorldPos = hrp.Position + Vector3.new(0, 2, 0) + (baseCamCFrame.RightVector * -screenOffset * 2)
	local screenPos, onScreen = camera:WorldToScreenPoint(uiWorldPos) -- WorldToScreenPoint projects 3D position to 2D screen

	buttonsFrame.Visible = onScreen -- Hides buttons if position is behind camera
	if onScreen then
		buttonsFrame.Position = UDim2.new(0, screenPos.X, 0, screenPos.Y) -- Update button position
	end
end)

-- Play transition and cleanup
local function startPlayTransition()
	IS_TRANSITIONING = true

	for _, child in ipairs(buttonsFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			child.Active = false -- Disable button clicks
			child.Selectable = false
			child.Interactable = false
		end
	end

	local wipeInfo = TweenInfo.new(1, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
	TweenService:Create(topBar, wipeInfo, {Rotation = (40), Size = UDim2.new(3, 0, 3, 0)}):Play() -- Expand top bar for wipe
	local bottomTween = TweenService:Create(bottomBar, wipeInfo, {
		Rotation = 40,
		Size = UDim2.new(3, 0, 3, 0) -- Expand bottom bar for wipe
	})
	bottomTween:Play()
	bottomTween.Completed:Wait() -- Wait for wipe to finish
	task.wait(0.4)

	IN_MENU = false
	buttonsFrame:Destroy() -- Remove menu buttons
	if titlePart then titlePart:Destroy() end -- Remove 3D title

	if renderConnection then
		renderConnection:Disconnect() -- Disconnects render loop
		renderConnection = nil
	end

	if dofEffect then dofEffect:Destroy() end -- Clean up depth of field
	if bloomEffect then bloomEffect:Destroy() end -- Clean up bloom
	if colorGradeEffect then colorGradeEffect:Destroy() end -- Clean up color correction
	if rimLight then rimLight:Destroy() end -- Remove rim light
	if menuAnimationTrack then menuAnimationTrack:Stop(0.3) end -- Stop idle animation

	-- Restore camera, controls and lighting
	camera.CameraType = Enum.CameraType.Custom -- Restore player camera
	hrp.Anchored = false -- Unanchor character

	if character:FindFirstChild("Animate") then
		character.Animate.Disabled = false -- Re enable character animations
	end

	local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	TweenService:Create(camera, fadeInfo, { FieldOfView = CONFIG.GAME_FOV }):Play() -- Restore default FOV
	TweenService:Create(Lighting, fadeInfo, { ClockTime = originalClockTime }):Play() -- Restore original clock time
	TweenService:Create(topBar, fadeInfo, { BackgroundTransparency = 1 }):Play() -- Fade out top bar

	local finalFade = TweenService:Create(bottomBar, fadeInfo, { BackgroundTransparency = 1 }) -- Fade out bottom bar
	finalFade:Play()
	finalFade.Completed:Wait()
	menuGui:Destroy() -- Clean up menu GUI
end

-- Button listeners
for _, button in ipairs(buttonsFrame:GetChildren()) do
	if button:IsA("TextButton") then
		button.MouseEnter:Connect(function()
			onButtonHover(button, true) -- Play hover effect
			if not IS_TRANSITIONING then hoverSound:Play() end		
		end)

		button.MouseLeave:Connect(function()
			onButtonHover(button, false) -- Reset hover effect
		end)

		button.MouseButton1Click:Connect(function()
			if IS_TRANSITIONING then return end

			clickSound:Play() -- Play click sound
			if button.Name == "PlayButton" then
				startPlayTransition() -- Start play transition
			elseif button.Name == "SettingsButton" then
				print("Settings button clicked")
			elseif button.Name == "ShopButton" then
				print("Shop button clicked")
			end
		end)
	end
end
