---@class FieldManager
FieldManager = CpObject()

-- Constructor
function FieldManager:init(number)
	print("FieldManager:init "..tostring(number))
	self.combinesOnField = {}
	self.unloadersOnField ={}
	self.myID = number
end

function FieldManager:addCombineToField(combine)
	if not self.combinesOnField[combine] then
		self.combinesOnField[combine] = g_combineUnloadManager.combines[combine]
		print("Manager"..self.myID..": add to field: "..tostring(combine.name))
	end
end

function FieldManager:addUnloaderToField(unloader)
	if not self.unloadersOnField[unloader] then
		self.unloadersOnField[unloader] = {}
		print("Manager"..self.myID..":add to field: "..tostring(unloader.name))
	end
end

function FieldManager:deleteUnloaderFromField(unloader)
	if self.unloadersOnField[unloader] then
		self.unloadersOnField[unloader] = nil
		print("Manager"..self.myID.."delete from field: "..tostring(unloader.name))
	end
end

function FieldManager:getCombineToUnloader(unloader)
	local combine = self:getChopperWithLeastUnloaders()
	local unloaderNumber = g_combineUnloadManager:getNumUnloaders(combine)
	if unloaderNumber == 0 then
		return combine
	elseif unloaderNumber <2 then
		local prevTractor = g_combineUnloadManager:getUnloaderByNumber(unloaderNumber, combine)
		if prevTractor.cp.driver:getFillLevelPercent() > unloader.cp.driver:getFillLevelThreshold() then
			return combine
		end
	end
end

function FieldManager:getChopperWithLeastUnloaders()
	local chopperToReturn = {}
	local amountUnloaders = math.huge
	for chopper,data in pairs(self.combinesOnField) do
		if data.isChopper then
			if amountUnloaders > #data.unloaders then
				chopperToReturn = chopper
				amountUnloaders = #data.unloaders
			end
		end
	end
	return chopperToReturn
end



---@class CombineUnloadmanager
CombineUnloadManager = CpObject()

-- Constructor
function CombineUnloadManager:init()
	print("CombineUnloadManager:init()")
	self.combines = {}
	self.unloadersOnFields ={}

end

g_combineUnloadManager = CombineUnloadManager()

function CombineUnloadManager:addCombineToList(combine)
	if combine:getPropertyState() == Vehicle.PROPERTY_STATE_SHOP_CONFIG then
		return
	end
	print(string.format("CombineUnloadmanager: added %s to list",tostring(combine.name)))
	self.combines[combine]= {
		isChopper = courseplay:isChopper(combine);
		isCombine = courseplay:isCombine(combine) and not courseplay:isChopper(combine);
		isDriving = false;
		isOnFieldNumber = 0;
		fillLevel = 0;
		leftOkToDrive = false;
		rightOKToDrive = false;
		pipeOffset = 0;
		unloaders = {};
	}
end

function CombineUnloadManager:removeCombineFromList(combine)
	if self.combines[combine] then
		print(string.format("CombineUnloadmanager: removed %s from list",tostring(combine.name)))
		self.combines[combine] = nil
	end
end

function CombineUnloadManager:releaseUnloaderFromCombine(unloader,combine)
	if self.combines[combine] then
		for i=1,#self.combines[combine].unloaders do
			if self.combines[combine].unloaders[i] == unloader then
				table.remove(self.combines[combine].unloaders,i)
				print(string.format("CombineUnloadmanager: released nr%d from combine",i))
			end
		end
	end
end


function CombineUnloadManager:giveMeACombineToUnload(unloader)
	if self.unloadersOnFields[unloader] and self.unloadersOnFields[unloader] > 0 then
		local combine = self.fieldManagers[self.unloadersOnFields[unloader]]:getCombineToUnloader(unloader)
		if combine ~= nil then
			table.insert(self.combines[combine].unloaders,unloader)
			return combine
		end
	end
end

function CombineUnloadManager:enterField(unloader)
	local unloaderOnFieldNumber = unloader.cp.searchCombineOnField > 0 and unloader.cp.searchCombineOnField or self:getFieldNumber(unloader)
	if self.unloadersOnFields[unloader] == nil then
		if unloaderOnFieldNumber > 0  then
			self.fieldManagers[unloaderOnFieldNumber]:addUnloaderToField(unloader)
			self.unloadersOnFields[unloader] = unloaderOnFieldNumber
		end
	elseif unloaderOnFieldNumber ~= self.unloadersOnFields[unloader] then
		self.fieldManagers[self.unloadersOnFields[unloader]]:deleteUnloaderFromField(unloader)
		self.fieldManagers[unloaderOnFieldNumber]:addUnloaderToField(unloader)
		self.unloadersOnFields[unloader]=unloaderOnFieldNumber
	end
end

function CombineUnloadManager:leaveField(unloader)
	self.fieldManagers[self.unloadersOnFields[unloader]]:deleteUnloaderFromField(unloader)
	self.unloadersOnFields[unloader] = nil
end

function CombineUnloadManager:onUpdate()
	self:updateCombinesAttributes()
	self:updateFieldManagers()
end

function CombineUnloadManager:updateFieldManagers()
	if self.fieldManagers == nil and #g_fieldManager:getFields() > 0 then
		self.fieldManagers = {}
		for i=1,#g_fieldManager:getFields() do
			self.fieldManagers[i] = FieldManager(i)
		end
	end
end


function CombineUnloadManager:updateCombinesAttributes()
	--update attributes
	for combine,attributes in pairs (self.combines) do
		attributes.isDriving = combine:getIsCourseplayDriving()
		attributes.isOnFieldNumber = self:getFieldNumber(combine)
		if attributes.isOnFieldNumber>0 and self.fieldManagers then
			self.fieldManagers[attributes.isOnFieldNumber]:addCombineToField(combine)
		end
		attributes.leftOkToDrive, attributes.rightOKToDrive = self:getOnFieldSituation(combine)
		attributes.pipeOffset = self:getPipeOffset(combine)
		attributes.fillLevel = self:getCombinesFillLevelPercent(combine)
		if attributes.measuredBackDistance == nil then
			self:raycastBack(combine)
		end
		for name,value in pairs (attributes) do
			--print(string.format("%s: %s",tostring(name),tostring(value)))
		end
		renderText(0.2,0.105,0.02,string.format("leftOK: %s; rightOK:%s numUnloaders:%d",tostring(attributes.leftOkToDrive),tostring(attributes.rightOKToDrive),#attributes.unloaders))
	end
end

function CombineUnloadManager:getIsChopper(chopper)
	return self.combines[chopper].isChopper
end
function CombineUnloadManager:getIsCombine(combine)
	return self.combines[combine].isCombine
end

function CombineUnloadManager:getCombinesPipeOffset(combine)
	return self.combines[combine].pipeOffset
end
function CombineUnloadManager:getPossibleSidesToDrive(combine)
	return self.combines[combine].leftOkToDrive, self.combines[combine].rightOKToDrive;
end

function CombineUnloadManager:getFieldNumber(vehicle)
	local positionX,_,positionZ = getWorldTranslation(vehicle.cp.DirectionNode or vehicle.rootNode);
	return courseplay.fields:getFieldNumForPosition( positionX, positionZ )
end

function CombineUnloadManager:getNumUnloaders(combine)
	return #self.combines[combine].unloaders
end

function CombineUnloadManager:getUnloadersNumber(unloader, combine)
	local number = 0
	for i=1,#self.combines[combine].unloaders do
		if self.combines[combine].unloaders[i] == unloader then
			number = i
			break
		end
	end
	return number
end

function CombineUnloadManager:getUnloaderByNumber(number, combine)
	return self.combines[combine].unloaders[number]
end


function CombineUnloadManager:getPipeOffset(combine)
	if self:getIsChopper(combine) then
		return (combine.cp.workWidth/2)+ 3
	elseif self:getIsCombine(combine) then
		local dischargeNode = combine:getCurrentDischargeNode().node
		local dnX,dnY,dnZ = getWorldTranslation(dischargeNode)
		local baseNode = self:getPipesBaseNode(combine)
		local tX,tY,tZ = getWorldTranslation(baseNode)
		local pipeOffsetX = worldToLocal(combine.cp.DirectionNode,tX,tY,tZ)
		local distance = courseplay:distance(dnX,dnZ, tX,tZ)
		--print(string.format(" pipeOffsetX:%s; distance:%s = %s  measured:%s",tostring(pipeOffsetX),tostring(distance),tostring(distance+pipeOffsetX),tostring(measured)))
		if pipeOffsetX > 0 then
			return pipeOffsetX + distance
		elseif pipeOffsetX < 0 then
			return pipeOffsetX - distance
		end
	end
	return 0
end

function CombineUnloadManager:getPipesBaseNode(combine)
	if self:getIsChopper(combine) then
		for i=1,#combine.spec_pipe.nodes do
			local node = combine.spec_pipe.nodes[i]
			if node.autoAimYRotation then
				return node.node
			end
		end
	elseif self:getIsCombine(combine) then
		--TODO find a cleaner way to figure out the getPipesBaseNode
		local dischargeNode = combine:getCurrentDischargeNode().node
		local lastParent = dischargeNode
		while true do
			--print(string.format("   %s: %s",tostring(lastParent),tostring(getName(lastParent))))
			if getName(lastParent) == 'pipe' then
				return lastParent
			end

			lastParent = getParent(lastParent)
		end
	end
end

function CombineUnloadManager:getCombinesFillLevelPercent(combine)
	local dischargeNode = combine:getCurrentDischargeNode()
	return combine:getFillUnitFillLevelPercentage(dischargeNode.fillUnitIndex)*100
end



function CombineUnloadManager:getCombinesMeasuredBackDistance(combine)
	return self.combines[combine].measuredBackDistance
end

function CombineUnloadManager:getOnFieldSituation(combine)
	local offset = self:getPipeOffset(combine)

	local tractor = combine;
	if courseplay:isAttachedCombine(combine) then
		tractor = combine:getAttacherVehicle();
	end;

	-- get world directions

	local node = combine.cp.DirectionNode or combine.rootNode;
	local straightDirX,_,straightDirZ = localDirectionToWorld(node, 0, 0, 1);
	local leftDirX,_,leftDirZ = localDirectionToWorld(node, 1, 0, 0);
	local rightDirX,_,rightDirZ = localDirectionToWorld(node, -1, 0, 0);
	--set measurements of the box to check
	local boxWidth = 3;
	local boxLength = 6 + combine.cp.workWidth/2;
	--to get the box centered divide the measurements by 2
	local boxWidthCenter = boxWidth/2
	local boxLengthCenter = boxLength/2

	--get the coords of the 3 left box points
	local x, y, z = localToWorld(tractor.cp.DirectionNode, 0, 0, 0)-- -boxLengthCenter+);
	local lStartX = x + (leftDirX * (math.abs(offset)-boxWidthCenter))
	local lStartZ = z + (leftDirZ * (math.abs(offset)-boxWidthCenter))
	local lWidthX = lStartX + (leftDirX*boxWidth);
	local lWidthZ = lStartZ + (leftDirZ*boxWidth);
	local lHeightX = lStartX + (straightDirX*boxLength);
	local lHeightZ = lStartZ + (straightDirZ*boxLength);

	--get the coords of the 3 right box points
	local rStartX = x + (rightDirX * (math.abs(offset)-boxWidthCenter))
	local rStartZ = z + (rightDirZ * (math.abs(offset)-boxWidthCenter))
	local rWidthX = rStartX + (rightDirX*boxWidth);
	local rWidthZ = rStartZ + (rightDirZ*boxWidth);
	local rHeightX = rStartX + (straightDirX*boxLength);
	local rHeightZ = rStartZ + (straightDirZ*boxLength);

	--fruitType
	local fruitType = combine.spec_combine.lastValidInputFruitType
	local hasFruit = false
	if fruitType == nil or fruitType == 0 then
		hasFruit,fruitType = courseplay:areaHasFruit(x, z, nil, math.abs(offset), math.abs(offset))
	end
	local minHarvestable, maxHarvestable = 1,1
	if fruitType ~= 0  and fruitType ~= nil then
		maxHarvestable = g_fruitTypeManager.fruitTypes[fruitType].numGrowthStates
	end

	--cpDebug:drawLine(lStartX,y+1,lStartZ, 100, 0, 0, lWidthX,y+1,lWidthZ)
	--cpDebug:drawLine(lWidthX,y+1,lWidthZ, 100, 0, 0, lHeightX,y+1,lHeightZ)
	--cpDebug:drawLine(lHeightX,y+1,lHeightZ, 100, 0, 0, lStartX,y+1,lStartZ)

	--cpDebug:drawLine(rStartX,y+1,rStartZ, 0, 100, 0, rWidthX,y+1,rWidthZ)
	--cpDebug:drawLine(rWidthX,y+1,rWidthZ, 0, 100, 0, rHeightX,y+1,rHeightZ)
	--cpDebug:drawLine(rHeightX,y+1,rHeightZ, 0, 100, 0, rStartX,y+1,rStartZ)



	local leftFruit, totalAreaLeft = FieldUtil.getFruitArea(lStartX, lStartZ, lWidthX, lWidthZ, lHeightX, lHeightZ, {}, {}, fruitType, minHarvestable , maxHarvestable, 0, 0, 0,false);
	local rightFruit, totalAreaRight = FieldUtil.getFruitArea(rStartX, rStartZ, rWidthX, rWidthZ, rHeightX, rHeightZ, {}, {}, fruitType, minHarvestable , maxHarvestable, 0, 0, 0,false);
	local leftField = courseplay:isField(lWidthX,lWidthZ,0.1,0.1)
	local rightField = courseplay:isField(rWidthX,rWidthZ,0.1,0.1)

	--print(string.format("fruit:%s; leftFruit:%s; totalLeft:%s, leftField:%s, rightFruit:%s, totalRight:%s; rightField:%s",
	--tostring(fruitType),tostring(leftFruit),tostring(totalArealeft),tostring(leftField),tostring(rightFruit),tostring(totalArearight),tostring(rightField)))

	local leftOK = leftField and leftFruit < totalAreaLeft*0.05
	local rightOK = rightField and rightFruit < totalAreaRight*0.05
	return leftOK,rightOK
end

function CombineUnloadManager:raycastBack(chopper)
	local nx, ny, nz = localDirectionToWorld(chopper.cp.DirectionNode, 0, 0, 1)
	local x, y, z = localToWorld(chopper.cp.DirectionNode, 0, 1.5, -10)
	cpDebug:drawLine(x, y, z, 0, 100, 0, x+(nx*10), y+(ny*10), z+(nz*10))
	raycastAll(x, y, z, nx, ny, nz, 'raycastBackCallback', 10, self)
end

function CombineUnloadManager:raycastBackCallback(hitObjectId, x, y, z, distance, nx, ny, nz, subShapeIndex)
	if hitObjectId ~= 0 then
		--print("hitObject: "..tostring(hitObjectId).."; distance: "..tostring(distance))
		cpDebug:drawPoint(x, y, z, 1, 1 , 1);
		local object = g_currentMission:getNodeObject(hitObjectId)
		if object and self.combines[object] and self.combines[object].measuredBackDistance == nil then
			self.combines[object].measuredBackDistance = 10 - distance
			print(string.format("%s: measuredBackDistance(%s) = 10 - distance(%s)",tostring(object.name),tostring(self.combines[object].measuredBackDistance),tostring(distance)))
		else
			return true
		end
	end
end



