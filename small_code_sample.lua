local Debris = game:GetService("Debris")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local sharedGrappleFunctions = require(game:GetService("ReplicatedStorage"):WaitForChild("modules"):WaitForChild("shared"):WaitForChild("sharedGrappleFunctions")).new()
local ReplicatedStorageModules = game:GetService("ReplicatedStorage"):WaitForChild("modules")
local SpringModule = require(ReplicatedStorageModules:WaitForChild("Spring"))
local rayutilsModule = require(ReplicatedStorageModules:WaitForChild("client"):WaitForChild("rayUtil"))

local rs = game:GetService("ReplicatedStorage")
local events = rs:WaitForChild("events")
local fcts = events:WaitForChild("fcts")
local removeAnchorEvent = fcts:WaitForChild("removeAnchor")

local player = game:GetService("Players").LocalPlayer
local Mouse = player:GetMouse()

local Character = script:FindFirstAncestorWhichIsA("Model")
local moveMode = {}
moveMode.__index = moveMode

function moveMode.new(Name, MoveValues, KeysDown, sharedInstancesTable)
	
	
	local WallRunValues = MoveValues:WaitForChild("wallrunValues",1)
	local CameraVaules = MoveValues:WaitForChild("cameraValues")
	local self = {
		--camera values
		cameraSensitivityMultiplier = 0.25,
		
		--basics
		speed = 75,
		dampXZ = 0.96, --in physics, this is how fast you go to your max speed and how fast you restore to 0 speed. Reasonable values are between 0.9 and 0.99
		name = Name,
		stopSpeed = 4.99, --just used to prevent extreme slipperyness, as you start off at a minimum speed
		MIN_SPEED = 5, --just used to prevent extreme slipperyness, as you start off at a minimum speed

		--jump values
		minJumpCooldown = 0.2,
		DEFAULT_NUMBER_OF_JUMP_FRAMES = 15,
		collisionStrength = 1, -- a value between 1 and 2. 1 for no bounce. 2 for full reflection
		minCollisionDistance = 6, -- for collision detection
		minDistanceFromFloorToStartWallrun = 5,  -- for collision detection, should probably be less than minCollisionDistance
		defaultDoubleJumps = 1,
		
		frameGoal = CFrame.new(0,0,0),
		
		sharedInstances = sharedInstancesTable,
		
		--character values
		character = Character,
		root = Character:FindFirstChild("HumanoidRootPart",1),
		rootToFoot = Character:FindFirstChild("rootToFoot"),
		head = Character:FindFirstChild("Head",1),
		upperTorso = Character:FindFirstChild("UpperTorso",1),
		cameraPart = Character:FindFirstChild("CameraPart"),
		humanoid = Character:FindFirstChild("Humanoid",1),
		neck = Character:FindFirstChild("Head"):FindFirstChild("Neck"),
		waist = Character:FindFirstChild("UpperTorso"):FindFirstChild("Waist"),
		keysDown = KeysDown,
		canStartAnimationThisFrame = true
		
	}

	--[[
	The movement code also has a camera system for the movement system.
	We have a "fake part" called cameraPart that we tween to where the camera should be.
	Then we set the player's view camera (workspace.camera) to the tweened camera's position every frame.
	This leads to a smoother camera, good for the wallrunning tilt effect.
	]]
	self.cameraPart.Transparency = 0.95 -- sfor debugging - so we see the camera part (temp)
	self.rootToFootDistance = (self.character.HumanoidRootPart.Size.Y / 2) + self.character.LowerTorso.Size.Y + self.character.LeftUpperLeg.Size.Y + self.character.LeftLowerLeg.Size.Y + self.character.LeftFoot.Size.Y
	for _, desc in pairs(MoveValues:GetDescendants())do
		moveMode[desc.Name] = desc
	end 
	
	for _, desc in pairs(player:WaitForChild("playerValues"):GetDescendants()) do
		moveMode[desc.Name] = desc
	end
	
	self.currentAnchor = game.ReplicatedStorage.clientPrivateStorage.values.currentAnchor
	
	--Rotates the camera left and right when you hit the wall
	--built off of the Spring module from the Nevermore Engine, implementing Hooke's Law.
	local RollSpring = SpringModule.new(0)
	RollSpring.Speed = 15
	RollSpring.Damper = 0.9
	sharedInstancesTable.rollSpring = RollSpring
	
	self.rayutils = rayutilsModule.new()
	
	--GUN CAMERA ROTATION IMPORT
	self.charValues = self.character:WaitForChild("charValues")
	self.currentCharGunValues = self.charValues:WaitForChild("currentGunValues")
	self.currentCharGunCameraValues = self.currentCharGunValues:WaitForChild("cameraValues")
	--self.cameraRecoilPitch =  self.currentCharGunCameraValues:WaitForChild("cameraRecoilPitch")
	for _,v in pairs(self.currentCharGunCameraValues:GetDescendants()) do
		self[v.Name] = v
	end
	setmetatable(self, moveMode)
	
	return self
end

--update what we want the camera's position and rotation to be
--this is called the "goal".
function moveMode:updateCameraTweenGoal()
	--print("update cam regular movemode")
	--
	
	--if player moves mouse, rotate the camera
	local delta = UserInputService:GetMouseDelta() * UserInputService.MouseDeltaSensitivity * self.cameraSensitivityMultiplier
	
	self.yaw.Value = self.yaw.Value + delta.X 
	self.pitch.Value = math.clamp((self.pitch.Value + delta.Y),-89,89 + self.extraCameraRecoilPitch.Value)
	--print(tostring(self.camRotThisFrame.Value + Vector3.new(-self.pitch.Value, -self.yaw.Value, 0)))

	--if they're not wallrunning, don't add the wallrunning camera effect.
	if self.movementMode.Value ~= "wallrun" then
		self.sharedInstances.rollSpring.Target = 0
	end
	
	self.camRotThisFrame.Value = self.camRotThisFrame.Value + Vector3.new(math.clamp(-self.pitch.Value + self.extraCameraRecoilPitch.Value,-89,89), -self.yaw.Value, 0) + Vector3.new(0,self.extraCameraRecoilYaw.Value,0)
	
	local camRotThisFrame = self.camRotThisFrame.Value
	local wallrunRotation =  CFrame.fromOrientation(0,0,(math.rad(self.sharedInstances.rollSpring.Position)))
	local mouseRotation = CFrame.fromOrientation(math.rad(camRotThisFrame.X), math.rad(camRotThisFrame.Y), math.rad(camRotThisFrame.Z))
	--local gunPitchRotation = CFrame.fromOrientation(math.rad(self.cameraRecoilPitch.Value),0,0)
	--mouserotation is offset by wallrunRotation (right is offset by left (right first))
	--local baseRotation = CFrame.fromOrientation(math.rad())

	self.frameGoal =  (mouseRotation * wallrunRotation)	
	--self.camRotThisFrame.Value = self.camRotThisFrame.Value + Vector3.new(0,0,self.sharedInstances.rollSpring.Position)
	
end

--step 1: play a tween on a part that constantly goes to where the camera should be (every frame).
--step 2: set the player's camera position to the tween part (every frame).
--this makes a smooth, tweened camera.
function moveMode:applyCameraTweenGoal()
	--import gun's recoil from gun
	
	--CFrame.fromOrientation(math.rad(gunPitch),0,0) 
	--rotation
		
	--print(tostring(wallrunRotationRelative))
	--frameGoal = wallrunRotationRelative * mouseRotation
	--print(tostring(camRotThisFrame))
	--print(tostring(self.sharedInstances.rollSpring.Position))
	local posGoal = self.cameraPart.Position
	local tween = TweenService:Create(self.tweenPart, TweenInfo.new(0.01), {
		CFrame = self.frameGoal,
	})
	tween:Play()
	--set camera to tweenPart
	self.tweenPart.Position = posGoal
	workspace.CurrentCamera.CFrame = self.tweenPart.CFrame
	
	--reset, we re will calculate the goal rotation every frame. 
	self.camRotThisFrame.Value = Vector3.new(0,0,0)
end

function moveMode:isKeyDown(keycode)
	--[[
	if self.keysDown[keycode] == nil then
		return false
	end
	return self.keysDown[keycode]
	]]
	return UserInputService:IsKeyDown(keycode)
	
end

function moveMode:neverOverrideLast()
	self.canStartAnimationThisFrame = true -- is used to prevent an animation from starting after switching modes.

end

function moveMode:updateLast()
	
	--[[
	local tv = self.totalVelocity.Value
	if tv.X ~= 0 or tv.Z ~= 0 then
		self.lastNonzeroVelocity.Value = tv
	end	
	local lnzv = self.lastNonzeroVelocity.Value 
	]]
	
	--print("ended frame: " .. self.frameCounter.Value)
	self.frameCounter.Value = self.frameCounter.Value + 1
end

--if a player hits the floor, give them their double jumps back!
function moveMode:updateDoubleJumps()
	if self.humanoid.FloorMaterial ~= nil and self.humanoid.FloorMaterial ~= Enum.Material.Air then
		--refresh jumps
		self.doubleJumpsLeft.Value = self.defaultDoubleJumps
	end
end

function moveMode:updateFirst()
	--local jumpsLeft = self.doubleJumpsLeft.Value
	--[[
	print("double jumps left: " .. jumpsLeft)
	local result = self:fireRay(self.root.Position, self.root.CFrame.UpVector * -1, 100)
	if result == nil then
		print("ERROR: nil m8??????")
		return
	end
	local distanceFromFloor = (self.root.Position - result.Position).Magnitude
	]]
	
	--[[
	if self.humanoid.FloorMaterial ~= nil and self.humanoid.FloorMaterial ~= Enum.Material.Air then
		--refresh jumps
		self.doubleJumpsLeft.Value = self.defaultDoubleJumps
	end
	]]
end

-- Gets the left/right direction vector of the player.
--IIRC, this is so when we are wallrunning, we only move the player in the X and Z direction of the wall, not the Y (not up and down the wall)
function moveMode:getCameraDirVectorXZ()
	local camera = workspace.CurrentCamera
	local dirVector = Vector3.new(0,0,0) -- X and Z, not X and Y. See code below.
	local pressedKeysString = ""
	if (self.lastUpDownKeyPressed.Value == Enum.KeyCode.W.Value and self:isKeyDown(Enum.KeyCode.W) or (self:isKeyDown(Enum.KeyCode.S) == false and self:isKeyDown(Enum.KeyCode.W))) then
		pressedKeysString = pressedKeysString .. "W"
		dirVector = dirVector + camera.CFrame.LookVector
	end

	if (self.lastUpDownKeyPressed.Value == Enum.KeyCode.S.Value and self:isKeyDown(Enum.KeyCode.S) or (self:isKeyDown(Enum.KeyCode.W) == false and self:isKeyDown(Enum.KeyCode.S))) then
		pressedKeysString = pressedKeysString .. "S"
		dirVector = dirVector -  camera.CFrame.LookVector
	end

	if (self.lastLeftRightKeyPressed.Value == Enum.KeyCode.A.Value and self:isKeyDown(Enum.KeyCode.A) or (self:isKeyDown(Enum.KeyCode.D) == false and self:isKeyDown(Enum.KeyCode.A)))   then
		pressedKeysString = pressedKeysString .. "A"
		dirVector = dirVector - camera.CFrame.RightVector
	end

	if (self.lastLeftRightKeyPressed.Value == Enum.KeyCode.D.Value and self:isKeyDown(Enum.KeyCode.D)) or (self:isKeyDown(Enum.KeyCode.A) == false and self:isKeyDown(Enum.KeyCode.D)) then
		pressedKeysString = pressedKeysString .. "D"
		dirVector = dirVector + camera.CFrame.RightVector
	end

	return dirVector
end

-- dirVector is a vector representing the direction the player wants to move.
-- we grab that diretion and move the player by their current SPEED amount.
-- (it's more complicated than just SPEED, but yeah)
function moveMode:updateDirVector()

	local fullDir = self:getCameraDirVectorXZ()
	local xzDir = fullDir * Vector3.new(1,0,1)
	if xzDir.Magnitude > 0 then
		xzDir = xzDir.Unit
	end
	self.dirVector.Value = xzDir
	
end

--overrided by subclasses to do stuff when we enter or exit a method of moving
function moveMode:onStart()
	
end
function moveMode:onEnd()

end

--swaps between movement modes like walking / wallrunning
function moveMode:setMode(newModeName)
	--print("old mode: " .. self.name .. " new mode: " .. newModeName)
	self.sharedInstances[self.name]:onEnd()
	self.movementMode.Value = newModeName 
	self.sharedInstances[newModeName]:onStart()
	
end

function moveMode:stopAnimation(animName)
	local foundAnim = self.animTracks[animName]
	if foundAnim == nil then
		print("ERROR: DID NOT FIND STOPPING ANIMATOIN")
		return
	end
	foundAnim:Stop()
end

function moveMode:stopAllAnimations()
	for _, anim in pairs(self.animTracks) do
		if anim.isPlaying then
			anim:Stop()
		end
	end
end

function moveMode:playAnimation(animName)	
	if self.canStartAnimationThisFrame == false then
		return
	end
	--print("trying to play animation " .. animName .. " from " .. self.name)
	local foundAnim = self.animTracks[animName]
	if foundAnim.isPlaying == true then
		--print("animation is already playing for " .. animName)
		return
	end
	if foundAnim == nil then
		--print("ERROR: ANIMATION DNE")
		return 
	end
	--stop move animations that aren't the current
	for _, anim in pairs(self.animTracks) do
		if anim.isPlaying and anim ~= foundAnim then
			anim:Stop()
		end
	end
	foundAnim:Play()
end

function moveMode:setGravity()
	workspace.Gravity = 196.2
end

function moveMode:groundTotalVelocity()
	--[[
	local xzMag = (self.totalVelocity.Value * Vector3.new(1,0,1)).Magnitude
	if xzMag < self.stopSpeed then
		self.totalVelocity.Value = self.totalVelocity.Value * Vector3.new(0,1,0)
	end
	]]
	
	local dirWithSpeed = Vector3.new(self.dirVector.Value.X * self.speed, 0,self.dirVector.Value.Z * self.speed)
	if (math.abs(self.totalVelocity.Value.X) + math.abs(self.totalVelocity.Value.Z) < self.stopSpeed) and (dirWithSpeed.X == 0 and dirWithSpeed.Z == 0) then
		self.totalVelocity.Value = self.totalVelocity.Value * Vector3.new(0,1,0)
	end
	
end

--if you don't know how damping based acceleration / velocity movement works, don't read this.
function moveMode:updateVelocity()
	
	--print("CALLING DEFAULT UPDATE VLEOCITY")
	local incrementAmount = Vector3.new(0,0,0)
	
	--enforce minimum speed
	local currentXZSpeed = self.totalVelocity.Value --* Vector3.new(1,0,1)
	
	local XZMagnitude = currentXZSpeed.Magnitude
	-- if we are under the minimum speed, but the player wants to move...
	-- then let them start moving at the minimum speed.
	if XZMagnitude < self.MIN_SPEED and (self.dirVector.Value.Magnitude > 0) then
		incrementAmount = self.dirVector.Value.Unit * self.MIN_SPEED -- * 1.05
		self.totalVelocity.Value = Vector3.new(0,0,0)
		self.totalVelocity.Value = self.totalVelocity.Value + incrementAmount
	end	
	
	local dot = self.dirVector.Value:Dot(currentXZSpeed)

	--add incremented speed. We add speed to the player's total speed 60~ times per second. This is how cars (in this case, players), accelerate and deccelerate smoothly
	local dirWithSpeed = Vector3.new(self.dirVector.Value.X * self.speed, 0,self.dirVector.Value.Z * self.speed)
	local fpsFraction = 1/workspace:GetRealPhysicsFPS()
	incrementAmount =  Vector3.new(dirWithSpeed.X * fpsFraction, 0, dirWithSpeed.Z * fpsFraction) -- increment by fps and speed
	self.totalVelocity.Value = self.totalVelocity.Value + incrementAmount
	
	--dont damp gravity. Damp XZ.
	local dampAmount = Vector3.new(self.dampXZ, 1, self.dampXZ)
	self.totalVelocity.Value = self.totalVelocity.Value * dampAmount
	
	--damp gravity seperately
	local GRAVITY_DAMPING = 0.99
	self.totalVelocity.Value = self.totalVelocity.Value * Vector3.new(1,GRAVITY_DAMPING,1)
	
	--add root gravity
end

--applies the speed we should be at (the totalVelocity we calculated using physics + Roblox's gravity) to the player's actual character (root.AssemblyLinearVelocity)
function moveMode:applyVelocityToRoot()
	self.root.AssemblyLinearVelocity = self.totalVelocity.Value + Vector3.new(0,self.root.AssemblyLinearVelocity.Y,0) -- add 
end

--fires a ray in the direction we should be moving to detect if there is anything in the way.
--@returns NIL (no collision) or RAYCAST RESULT on collision
function moveMode:getCollisionResult()
	
	local result = self:fireRay(self.rootToFoot.Position,self.totalVelocity.Value, 100)
	if result == nil then
		--no wall nearby
		--print("no wall nearby")
		return nil
	end
	--print("COLLIDE ANGLE IS: " .. math.deg(math.asin(self.totalVelocity.Value.Unit.Y)))
	--self:visualizeRay(self.root.Position, self.root.Position + self.totalVelocity.Value, Color3.new(1, 0.933333, 0.00392157),0.1)

	local distance = (result.Position - self.head.Position).Magnitude
	--print("dist: " .. distance)
	if distance > self.minCollisionDistance then
		--wall is too far away to collide
		--print("wall too far")
		return nil
	end

	return result
end

--TODO - make a method based off of subtraction distance 
function moveMode:isHighEnoughForWallRun()
	--[[
	local dist = (self.rootToFoot.Position.Y - hitPos.Y)
	print("dist is: " .. dist)
	if dist < 0 then
		print("high enough")
		return true
	end
	print("not high enough")
	return false
	]]

	--see if we should connect them to the wall
	local toFloorResult = self:fireRay(self.root.Position, self.root.CFrame.UpVector * -1, 1000)
	local distanceFromFloor = 0
	if toFloorResult == nil then
		warn("NOTHING UNDER PLAYER, THEYRE PROBABLY HIGH UP, FALLING BACK ON HIGH DISTANCEFROMFLOOR")
		distanceFromFloor = 1000
		return true
	end
	distanceFromFloor = (self.root.Position - toFloorResult.Position).Magnitude

	if distanceFromFloor > self.minDistanceFromFloorToStartWallrun then
		return true
	end
	return false
	
	
end

--we only want to do a wallrun if we are higher up on the wall.
function moveMode:isCollideTooHighForWallrun(hitPos)
	local dist = (hitPos.Y - self.rootToFoot.Position.Y)
	--print("dist is: " .. dist)
	if dist > 3.5 then
		return true
	end
	return false
end

-- (DISABLED) so our collision system bounce player off of objects.
function moveMode:bounceCharacter(normal)
	if false then
		local reflection = (self.totalVelocity.Value - (self.collisionStrength * self.totalVelocity.Value:Dot(normal) * normal))
		self.totalVelocity.Value = Vector3.new(reflection.X, 0, reflection.Z) 	
	end
end

--returns true if we can reasonably start a wallrun
--returns false otherwise
function moveMode:shouldWallRun(collisionResult)
	
	if collisionResult.Instance:FindFirstChild("_notWallRunnable") then
		return false
	end
	
	if self:isCollideTooHighForWallrun(collisionResult.Position) then
		self:removeGrappleIfExists()
		return false
	end

	if self:isHighEnoughForWallRun() == false then
		self:removeGrappleIfExists()
		return false
	end
	
	if (self.humanoid.FloorMaterial == Enum.Material.Air) and self:isHighEnoughForWallRun() == false then
		return false
	end

	if self.movementMode == "wallrun" then
		return false
	end
	return true
end

function moveMode:removeGrappleIfExists()
	if sharedGrappleFunctions:removeAnchor(player.Name) then
		removeAnchorEvent:FireServer()
	end
end

--performs actions based off of collisions that we detect
function moveMode:handleCollisions()
	local collisionResult = self:getCollisionResult()
	if collisionResult == nil then
		return
	end
	local normal = collisionResult.Normal.Unit
	
	--formula to reflect bullets off a normal is recycled.
	self:bounceCharacter(normal)
	--self:visualizeRay(self.root.Position, reflection + self.root.Position, Color3.new(1, 0.933333, 0.00392157),0.1)
	--self:makeDebugPart(collisionResult.Position, Color3.new(1, 0, 0),Vector3.new(1,1,1),3)
	
	--wallruns if we performed that kind of collision to a wall.
	if self:shouldWallRun(collisionResult) then
		if self.movementMode.Value == "grapple" then
			moveMode:removeGrappleIfExists()
		end
		self:setWallrunRay(collisionResult)
		self:setMode("wallrun")
	end
end

function moveMode:shouldSwapToGrapple()
	if self.currentAnchor.Value == nil then
		return false
	end
	return true
end

function moveMode:swapToGrappleIfShould()
	if self:shouldSwapToGrapple() then
		self:setMode("grapple")
	end

end

function moveMode:setWallrunRay(rayresult)
	if rayresult == nil then
		print("ERROR: NIL RAY PASSED")
		return
	end
	self.lastWallRayPosition.Value = rayresult.Position
	self.lastWallRayNormal.Value = rayresult.Normal
	self.lastWallRayInstance.Value = rayresult.Instance
end

function moveMode:updateAesthetics()

	--[[
	--camera based update root cframe
	local lookDir = (workspace.CurrentCamera.CFrame.LookVector) * Vector3.new(1,0,1)
	self.root.CFrame = CFrame.new(self.root.CFrame.Position, self.root.CFrame.Position + lookDir)
	]]
	
	local mouseResult = self.rayutils:getMouseRay()
	local targetPos = nil
	if mouseResult ~= nil and mouseResult.Position ~= nil then
		targetPos = mouseResult.Position
	else
		targetPos = Mouse.hit.Position
	end
	
	--FACE MOUSE DIRECTION. FACE DIRECTION OF MOUSE
	self.root.CFrame = CFrame.new(self.root.CFrame.Position, Vector3.new(targetPos.X, self.root.CFrame.Position.Y, targetPos.Z))
	
	local pitch = math.asin((targetPos - self.root.CFrame.Position).Unit.Y)	
	--print("pitch is ".. math.deg(pitch))
	self.waist.C0 = CFrame.new(0,0,0) * CFrame.Angles(pitch,0,0)

end

function moveMode:handleJumpRequest()
	if self._isInMinJumpCooldown then
		print("in min jump cooldown")
		return
	end	
	--[[
	--isIncrementingJumpValue.Value = true
	if self.humanoid:GetState() == Enum.HumanoidStateType.Freefall then
		print("already in freefall")
		return
	end
	]]
	--[[
	local result = self:fireRay(self.root.Position, self.root.CFrame.UpVector * -1, 100)
	if result == nil then
		--print("floor too far?")
		return
	end
	local distanceFromFloor = (self.root.Position - result.Position).Magnitude
	]]
	--the distance from floor check is so we can jump on wedges
	if (self.humanoid.FloorMaterial == nil or self.humanoid.FloorMaterial == Enum.Material.Air) then--and distanceFromFloor > 4 then
		
		local jumpsLeft = self.doubleJumpsLeft.Value
		
		if jumpsLeft <= 0 then
			print("out of double jumps")
			return
		end
		--print("======= double jumping ==========")
		self.doubleJumpsLeft.Value  = self.doubleJumpsLeft.Value - 1
		
		--local previousY = self.totalVelocity.Value.Y
		--print("previous y is: " .. previousY)
		self.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		--self.totalVelocity.Value = Vector3.new(self.totalVelocity.Value.X, previousY, self.totalVelocity.Value.Z)
		
		print("DOUBLE JUMPING " .. self.doubleJumpsLeft.Value)
		return
	end
	--totalVelocity.Value = totalVelocity.Value + Vector3.new(0,10,0)

	--print("doing self jump but no code: TODO jump")
	
	--[[
	self._isInMinJumpCooldown = true
	wait(self.minJumpCooldown)
	self._isInMinJumpCooldown = false
	]]
end

--just a raycasting wrapper I use
function moveMode:fireRay(position, direction, distance)
	return self.rayutils:fireRay(position, direction, distance, {self.character})
end

--just used to visualize rays by me, for debugging raycasts
function moveMode:visualizeRay(originPos, targetPos, color, lineLife)
	self.rayutils:visualizeRay(originPos, targetPos, color, lineLife)
end

--just makes a part, used for debugging
function moveMode:makeDebugPart(position,life)
	self.rayutils:makeDebugPart(position, life)
end
return moveMode
