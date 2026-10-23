BONK_CLASSES = {
	{ token = "WARRIOR", name = "Warrior", races = { "HUMAN", "DWARF", "NIGHTELF", "GNOME", "ORC", "SCOURGE", "TAUREN", "TROLL" } },
	{ token = "PALADIN", name = "Paladin", races = { "HUMAN", "DWARF" } },
	{ token = "HUNTER",  name = "Hunter",  races = { "DWARF", "NIGHTELF", "ORC", "TAUREN", "TROLL" } },
	{ token = "ROGUE",   name = "Rogue",   races = { "HUMAN", "DWARF", "NIGHTELF", "GNOME", "ORC", "SCOURGE", "TROLL" } },
	{ token = "PRIEST",  name = "Priest",  races = { "HUMAN", "DWARF", "NIGHTELF", "SCOURGE", "TROLL" } },
	{ token = "SHAMAN",  name = "Shaman",  races = { "ORC", "TAUREN", "TROLL" } },
	{ token = "MAGE",    name = "Mage",    races = { "HUMAN", "GNOME", "SCOURGE", "TROLL" } },
	{ token = "WARLOCK", name = "Warlock", races = { "HUMAN", "GNOME", "ORC", "SCOURGE" }, locked = 1 },
	{ token = "DRUID",   name = "Druid",   races = { "NIGHTELF", "TAUREN" }, locked = 1 },
};

BONK_RACE_NAMES = {
	HUMAN = "Human", DWARF = "Dwarf", NIGHTELF = "Night Elf", GNOME = "Gnome",
	ORC = "Orc", SCOURGE = "Undead", TAUREN = "Tauren", TROLL = "Troll",
};

BONK_CLASS_TOKENS = {};
for _, class in BONK_CLASSES do
	BONK_CLASS_TOKENS[class.name] = class.token;
end

local NUM_STAT_ROWS = 8;
local INFO_HEIGHT = 520;
local INFO_CREATE_HEIGHT = 620;
local IRONMAN_NAME = "Ironmanmode";
local IRONMAN_TIP = "This character does not share gold or unlocks with other characters.";
local RACES_PER_ROW = 4;
local RACE_ROW_HEIGHT = 72;
local CREATE_LAYOUT = {
	{ "BonkHeroLookLabel", 26, -262 },
	{ "BonkHeroGenderButton1", 26, -284 },
	{ "BonkHeroLook1", 22, -342 },
	{ "BonkHeroLook2", 22, -372 },
	{ "BonkHeroLook3", 22, -402 },
	{ "BonkHeroLook4", 22, -432 },
	{ "BonkHeroLook5", 22, -462 },
	{ "BonkHeroNameLabel", 26, -506 },
	{ "BonkHeroNameEdit", 18, -520 },
};

local function Flag(condition)
	if ( condition ) then
		return 1;
	end
	return nil;
end

Bonk = {
	classIndex = 1,
	raceIndex = 1,
	sex = 1,
	heroes = {},
	listLoaded = false,
	reuseList = false,
	creating = nil,
	wiping = nil,
	appliedRace = nil,
	screen = nil,
	refreshing = false,
	sceneDirty = false,
	sceneDelay = 0,
	startPicked = false,
	loginTried = false,
	reachedServer = false,
};

function BonkLogin_Connect()
	BonkLoginStatus:SetText("Connecting...");
	DefaultServerLogin(BONK_ACCOUNT, BONK_PASSWORD);
end

local OriginalAccountLoginOnShow = AccountLogin_OnShow;
function AccountLogin_OnShow()
	Bonk.reachedServer = false;
	Bonk.loginTried = false;
	OriginalAccountLoginOnShow();
	BonkHeroFrame:Hide();

	Bonk.listLoaded = false;
	Bonk.reuseList = false;
	Bonk.startPicked = false;
	Bonk.classIndex = 1;
	Bonk.raceIndex = 1;
	Bonk.creating = nil;
	Bonk.wiping = nil;
	Bonk.heroes = {};

	if ( not BONK_ACCOUNT or not EULAAccepted() or not TOSAccepted() ) then
		BonkLoginFrame:Hide();
		return;
	end

	BonkLogin_Begin();
end

function BonkLogin_Begin()
	AccountLoginUI:Hide();
	AccountLoginAccountEdit:ClearFocus();
	AccountLoginPasswordEdit:ClearFocus();
	BonkLoginFrame:Show();
	BonkLoginStatus:SetText("");

	if ( not Bonk.loginTried ) then
		Bonk.loginTried = true;
		BonkLogin_Connect();
	end
end

local OriginalShowUserAgreements = AccountLogin_ShowUserAgreements;
function AccountLogin_ShowUserAgreements()
	OriginalShowUserAgreements();
	if ( BONK_ACCOUNT and EULAAccepted() and TOSAccepted() and not TOSFrame:IsVisible() and AccountLogin:IsVisible() ) then
		BonkLogin_Begin();
	end
end

local OriginalAccountLoginOnKeyDown = AccountLogin_OnKeyDown;
function AccountLogin_OnKeyDown()
	if ( not BonkLoginFrame:IsVisible() ) then
		OriginalAccountLoginOnKeyDown();
	elseif ( arg1 == "ENTER" ) then
		BonkLogin_Connect();
	elseif ( arg1 == "ESCAPE" ) then
		AccountLogin_Exit();
	elseif ( arg1 == "PRINTSCREEN" ) then
		Screenshot();
	end
end

local OriginalSetGlueScreen = SetGlueScreen;
function SetGlueScreen(name)
	Bonk.screen = name;
	if ( name ~= "charselect" and name ~= "charcreate" ) then
		BonkHeroFrame:Hide();
	end
	OriginalSetGlueScreen(name);
end

local OriginalCharacterSelectOnShow = CharacterSelect_OnShow;
function CharacterSelect_OnShow()
	Bonk.reachedServer = true;
	local requestList = GetCharacterListUpdate;
	if ( Bonk.reuseList and Bonk.listLoaded and not Bonk.creating ) then
		GetCharacterListUpdate = UpdateCharacterList;
	end
	Bonk.reuseList = false;
	OriginalCharacterSelectOnShow();
	GetCharacterListUpdate = requestList;

	CharacterSelectUI:Hide();
	BonkHeroFrame:Show();

	if ( not Bonk.listLoaded ) then
		Bonk.sceneDelay = 1.0;
	end
	BonkHero_Refresh();
end

local BONK_REALM_CATEGORY = 1;

local OriginalGlueParentOnEvent = GlueParent_OnEvent;
function GlueParent_OnEvent(event)
	if ( event == "GET_PREFERRED_REALM_INFO" and BONK_ACCOUNT ) then
		SetPreferredInfo(BONK_REALM_CATEGORY, nil, nil);
		return;
	end
	OriginalGlueParentOnEvent(event);
end

local OriginalCharacterSelectOnEvent = CharacterSelect_OnEvent;
function CharacterSelect_OnEvent()
	if ( event == "SUGGEST_REALM" and BONK_ACCOUNT ) then
		SetGlueScreen("charselect");
		ChangeRealm(arg1, arg2);
		return;
	end
	OriginalCharacterSelectOnEvent();
	if ( event == "CHARACTER_LIST_UPDATE" ) then
		BonkHero_OnCharacterList();
	elseif ( event == "UPDATE_SELECTED_CHARACTER" and Bonk.listLoaded ) then
		local hero = Bonk.heroes[BONK_CLASSES[Bonk.classIndex].token];
		if ( hero and arg1 ~= hero.index ) then
			Bonk.sceneDirty = true;
		end
	end
end

function CharacterSelect_OnKeyDown()
	BonkHero_OnKeyDown();
end

local OriginalCharacterCreateOnShow = CharacterCreate_OnShow;
function CharacterCreate_OnShow()
	OriginalCharacterCreateOnShow();
	CharacterCreateFrame:Hide();
	BonkHeroFrame:Show();
	Bonk.appliedRace = nil;
	BonkHero_ApplyNewHero();
end

function CharacterCreate_OnKeyDown()
	BonkHero_OnKeyDown();
end

local OriginalGlueDialogOnEvent = GlueDialog_OnEvent;
function GlueDialog_OnEvent()
	local text = arg1;
	if ( event == "OPEN_STATUS_DIALOG" ) then
		text = arg2;
	end
	local success = text == CHAR_DELETE_SUCCESS or text == CHAR_CREATE_SUCCESS;
	local failed = not success and ((event == "OPEN_STATUS_DIALOG" and arg1 == "OKAY") or (event == "UPDATE_STATUS_DIALOG" and arg2));
	if ( Bonk.creating and failed ) then
		Bonk.creating = nil;
		BonkHero_SetStatus("");
	end
	local wipeRefused = Bonk.wiping and failed and Bonk.wiping.step == "create";
	if ( Bonk.wiping and failed ) then
		BonkHero_StopWipe("The account was not wiped.");
	end
	OriginalGlueDialogOnEvent();

	local shown = GlueDialogText:GetText();
	local noServer = shown == RESPONSE_FAILED_TO_CONNECT or shown == LOGIN_FAILED or shown == LOGIN_SERVER_DOWN or shown == REALM_LIST_FAILED
		or shown == RESPONSE_DISCONNECTED or shown == DISCONNECTED;
	if ( noServer ) then
		if ( BONK_COOP ) then
			GlueDialogText:SetText("The connection to the host was interrupted. Keep the launcher open and try Connect again. If the host closed the game, ask for a new invitation.");
		else
			GlueDialogText:SetText("The game couldn't connect. Try Connect again, or close the game and restart it from HoALauncher.exe.");
		end
		GlueDialogBackground:SetHeight(32 + GlueDialogText:GetHeight() + 8 + GlueDialogButton1:GetHeight() + 16);
		BonkLoginStatus:SetText("");
		Bonk.reachedServer = false;
		Bonk.loginTried = false;
	elseif ( wipeRefused ) then
		GlueDialogText:SetText("The account was not wiped because a hero is still left. Try again.");
		GlueDialogBackground:SetHeight(32 + GlueDialogText:GetHeight() + 8 + GlueDialogButton1:GetHeight() + 16);
	elseif ( Bonk.wiping and success and event == "UPDATE_STATUS_DIALOG" and arg2 ) then
		GlueDialog:Hide();
	end
end

local OriginalGlueDialogOnClick = GlueDialog_OnClick;
function GlueDialog_OnClick(index)
	local which = GlueDialog.which;
	OriginalGlueDialogOnClick(index);
	if ( Bonk.creating ) then
		Bonk.creating = nil;
		BonkHero_SetStatus("");
	end
	if ( Bonk.wiping and which ~= "BONK_WIPE" ) then
		BonkHero_StopWipe("Wipe stopped. Some heroes may already be gone.");
	end
end

GlueDialogTypes["BONK_QUIT"] = {
	text = "Quit Hordes of Azeroth?",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	OnAccept = function()
		QuitGame();
	end,
	OnCancel = function()
	end,
};

GlueDialogTypes["BONK_RETIRE"] = {
	text = "",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	showAlert = 1,
	OnAccept = function()
		DeleteCharacter(GlueDialog.data);
	end,
	OnCancel = function()
	end,
};

GlueDialogTypes["BONK_WIPE"] = {
	text = "Are you sure? This deletes all your heroes and all account progress: gold, Darkmoon Tickets, upgrades, Sayge's Fortunes, quests and Mastery. It cannot be undone.",
	button1 = TEXT(YES),
	button2 = TEXT(NO),
	showAlert = 1,
	OnAccept = function()
		BonkHero_StartWipe();
	end,
	OnCancel = function()
	end,
};

local function FormatGold(copper)
	copper = copper or 0;
	local gold = floor(copper / 10000);
	local silver = floor(mod(copper, 10000) / 100);
	local text = format("|cffeda55f%dc|r", mod(copper, 100));
	if ( gold > 0 or silver > 0 ) then
		text = format("|cffc7c7cf%ds|r ", silver)..text;
	end
	if ( gold > 0 ) then
		text = format("|cffffd700%dg|r ", gold)..text;
	end
	return text;
end

local function FormatTime(seconds)
	seconds = seconds or 0;
	local hours = floor(seconds / 3600);
	local minutes = floor(mod(seconds, 3600) / 60);
	if ( hours > 0 ) then
		return format("%d:%02d:%02d", hours, minutes, mod(seconds, 60));
	end
	return format("%d:%02d", minutes, mod(seconds, 60));
end

local function CurrentClass()
	return BONK_CLASSES[Bonk.classIndex];
end

local function CurrentHero()
	return Bonk.heroes[CurrentClass().token];
end

local function NewHeroRace()
	return CurrentClass().races[Bonk.raceIndex];
end

local function HeroStats(hero)
	if ( BONK_STATS and BONK_STATS.heroes ) then
		return BONK_STATS.heroes[hero.name];
	end
	return nil;
end

local function SetTexCoords(texture, coords)
	texture:SetTexCoord(coords[1], coords[2], coords[3], coords[4]);
end

local function RaceIconCoords(race, sex)
	local gender = "MALE";
	if ( sex == 2 ) then
		gender = "FEMALE";
	end
	return RACE_ICON_TCOORDS[race.."_"..gender];
end

function BonkHero_SetStatus(text)
	BonkHeroStatus:SetText(text);
end

function BonkHero_OnLoad()
	for index, class in BONK_CLASSES do
		local tile = getglobal("BonkHeroClassButton"..index);
		local column = mod(index - 1, 3);
		local row = floor((index - 1) / 3);
		tile:SetPoint("TOP", "BonkHeroClassPanel", "TOP", -96 + column * 96, -50 - row * 112);
		local icon = getglobal(tile:GetName().."Icon");
		icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes");
		SetTexCoords(icon, CLASS_ICON_TCOORDS[class.token]);
		getglobal(tile:GetName().."Class"):SetText(class.name);
	end

	for index = 1, 8 do
		local button = getglobal("BonkHeroRaceButton"..index);
		local column = mod(index - 1, RACES_PER_ROW);
		local row = floor((index - 1) / RACES_PER_ROW);
		button:SetPoint("TOPLEFT", "BonkHeroCreateFrame", "TOPLEFT", 30 + column * 74, -114 - row * RACE_ROW_HEIGHT);
	end

	for index = 1, NUM_STAT_ROWS do
		getglobal("BonkHeroStat"..index):SetPoint("TOPLEFT", "BonkHeroRecordFrame", "TOPLEFT", 30, -126 - (index - 1) * 24);
	end

	getglobal("BonkHeroGenderButton1Icon"):SetTexCoord(0, 0.5, 0, 1.0);
	getglobal("BonkHeroGenderButton2Icon"):SetTexCoord(0.5, 1.0, 0, 1.0);

	BonkHero_UpdateGold(nil);
end

function BonkHero_UpdateGold(stats)
	if ( not BONK_STATS or not BONK_STATS.gold ) then
		return;
	end
	if ( stats and stats.ironman ) then
		BonkHeroGoldLabel:SetText("Gold (This character only)");
		BonkHeroGold:SetText(FormatGold(stats.gold or 0));
	else
		BonkHeroGoldLabel:SetText("Gold (shared by all heroes)");
		BonkHeroGold:SetText(FormatGold(BONK_STATS.gold));
	end
	BonkHeroGoldFrame:Show();
end

function BonkHero_ToggleIronman()
	Bonk.ironman = BonkHeroIronman:GetChecked() and true or nil;
	if ( Bonk.ironman ) then
		PlaySound("igMainMenuOptionCheckBoxOn");
	else
		PlaySound("igMainMenuOptionCheckBoxOff");
	end
end

function BonkHero_ShowIronmanTip()
	BonkIronmanTipText:SetText(IRONMAN_TIP);
	BonkIronmanTip:SetHeight(BonkIronmanTipText:GetHeight() + 20);
	BonkIronmanTip:ClearAllPoints();
	BonkIronmanTip:SetPoint("BOTTOMLEFT", "BonkHeroIronman", "TOPRIGHT", 0, 0);
	BonkIronmanTip:Show();
end

function BonkHero_ReadHeroes()
	Bonk.heroes = {};
	local unknown;
	for index = 1, GetNumCharacters() do
		local name, race, class, level, zone, fileString, gender = GetCharacterInfo(index);
		local classToken = BONK_CLASS_TOKENS[class];
		if ( name and not (classToken and fileString) ) then
			unknown = name.." ("..tostring(class)..", "..tostring(fileString)..")";
		end
		if ( name and classToken and fileString and not Bonk.heroes[classToken] ) then
			local sex = 1;
			if ( gender and gender ~= 0 ) then
				sex = 2;
			end
			Bonk.heroes[classToken] = { index = index, name = name, race = strupper(fileString), level = level, sex = sex };
		end
	end
	if ( unknown ) then
		BonkHero_SetStatus("Could not read the class of "..unknown..".");
	end
end

local function IsSelectable(class)
	return not class.locked or Bonk.heroes[class.token];
end

local function SelectClassToken(classToken)
	for index, class in BONK_CLASSES do
		if ( class.token == classToken ) then
			Bonk.classIndex = index;
		end
	end
end

function BonkHero_OnCharacterList()
	BonkHero_ReadHeroes();

	if ( Bonk.wiping ) then
		Bonk.listLoaded = true;
		if ( Bonk.wiping.step == "create" ) then
			BonkHero_FinishWipe();
		else
			Bonk.wiping.sent = nil;
			Bonk.wiping.wait = BONK_WIPE_GAP;
			BonkHero_UpdateRoster();
		end
		return;
	end

	if ( Bonk.creating and Bonk.creating.ironmanSent ) then
		Bonk.creating.ironmanSent = nil;
		BonkHero_CreateCharacter();
		return;
	end

	if ( Bonk.creating ) then
		local hero = Bonk.heroes[Bonk.creating.class];
		if ( hero ) then
			Bonk.creating = nil;
			BonkHeroNameEdit:SetText("");
			BonkHero_EnterWorld(hero);
			return;
		end
	end

	Bonk.listLoaded = true;
	local count = GetNumCharacters();
	if ( not Bonk.startPicked and count > 0 ) then
		Bonk.startPicked = true;
		local start;
		for index = 1, count do
			if ( BONK_STATS and BONK_STATS.lastHero and GetCharacterInfo(index) == BONK_STATS.lastHero ) then
				start = index;
			end
		end
		if ( not start and CharacterSelect.selectedIndex and CharacterSelect.selectedIndex > 0 and CharacterSelect.selectedIndex <= count ) then
			start = CharacterSelect.selectedIndex;
		end
		if ( not start ) then
			start = 1;
		end
		local name, race, class = GetCharacterInfo(start);
		if ( BONK_CLASS_TOKENS[class] ) then
			SelectClassToken(BONK_CLASS_TOKENS[class]);
		end
	end

	BonkHero_Refresh();
end

function BonkHero_Refresh()
	if ( Bonk.refreshing ) then
		return;
	end
	Bonk.refreshing = true;
	BonkHero_UpdateRoster();
	BonkHero_UpdateInfo();
	Bonk.refreshing = false;

	Bonk.sceneDirty = true;
end

function BonkHero_UpdateRoster()
	local count = 0;
	local playable = 0;
	for index, class in BONK_CLASSES do
		local tile = getglobal("BonkHeroClassButton"..index);
		local icon = getglobal(tile:GetName().."Icon");
		local heroText = getglobal(tile:GetName().."Hero");
		local hero = Bonk.heroes[class.token];
		tile:SetChecked(Flag(index == Bonk.classIndex));
		if ( not class.locked ) then
			playable = playable + 1;
		end
		if ( hero ) then
			count = count + 1;
			icon:SetVertexColor(1.0, 1.0, 1.0);
			icon:SetAlpha(1.0);
			getglobal(tile:GetName().."Glow"):Show();
			heroText:SetText(hero.name);
			heroText:SetTextColor(1.0, 1.0, 1.0);
		elseif ( class.locked ) then
			icon:SetVertexColor(0.25, 0.25, 0.25);
			icon:SetAlpha(0.5);
			getglobal(tile:GetName().."Glow"):Hide();
			heroText:SetText("Locked");
			heroText:SetTextColor(0.4, 0.4, 0.4);
		else
			icon:SetVertexColor(0.45, 0.45, 0.45);
			icon:SetAlpha(0.7);
			getglobal(tile:GetName().."Glow"):Hide();
			heroText:SetText("+ New");
			heroText:SetTextColor(0.5, 0.5, 0.5);
		end
	end
	BonkHeroCount:SetText(count.." of "..playable.." classes have a hero");
end

function BonkHero_LayoutCreate(raceCount)
	local unusedRows = 2 - ceil(raceCount / RACES_PER_ROW);
	local lift = unusedRows * RACE_ROW_HEIGHT;
	for _, place in ipairs(CREATE_LAYOUT) do
		local frame = getglobal(place[1]);
		frame:ClearAllPoints();
		frame:SetPoint("TOPLEFT", "BonkHeroCreateFrame", "TOPLEFT", place[2], place[3] + lift);
	end
	BonkHeroInfoPanel:SetHeight(INFO_CREATE_HEIGHT - lift);
end

function BonkHero_UpdateInfo()
	local class = CurrentClass();
	local hero = CurrentHero();

	if ( hero ) then
		BonkHeroName:SetText(hero.name);
		local stats = HeroStats(hero) or {};
		local mastery = stats.mastery or 0;
		local detail = format("Mastery %d %s %s", mastery, BONK_RACE_NAMES[hero.race] or "", class.name);
		if ( stats.ironman ) then
			detail = detail.." (Ironman)";
		end
		BonkHeroDetail:SetText(detail);
		BonkHero_UpdateGold(stats);
		BonkHeroCreateFrame:Hide();
		BonkHeroInfoPanel:SetHeight(INFO_HEIGHT);
		BonkHeroRecordFrame:Show();
		BonkHero_UpdateRecord(hero);
		BonkHeroPlayButton:SetText("Play");
		return;
	end

	if ( Bonk.raceIndex > getn(class.races) ) then
		Bonk.raceIndex = 1;
	end
	BonkHeroName:SetText("New "..class.name);
	BonkHeroDetail:SetText(BONK_RACE_NAMES[NewHeroRace()].." "..class.name);
	BonkHeroRecordFrame:Hide();
	BonkHero_UpdateGold(nil);
	BonkHeroIronman:SetChecked(Flag(Bonk.ironman));
	BonkHero_LayoutCreate(getn(class.races));
	BonkHeroCreateFrame:Show();
	BonkHeroPlayButton:SetText("Create hero");

	for index = 1, 8 do
		local button = getglobal("BonkHeroRaceButton"..index);
		local race = class.races[index];
		if ( race ) then
			local icon = getglobal(button:GetName().."Icon");
			icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races");
			SetTexCoords(icon, RaceIconCoords(race, Bonk.sex));
			getglobal(button:GetName().."Label"):SetText(BONK_RACE_NAMES[race]);
			button:SetChecked(Flag(index == Bonk.raceIndex));
			button:Show();
		else
			button:Hide();
		end
	end
	BonkHeroGenderButton1:SetChecked(Flag(Bonk.sex == 1));
	BonkHeroGenderButton2:SetChecked(Flag(Bonk.sex == 2));
end

local function FormatPlayed(seconds)
	if ( not seconds or seconds <= 0 ) then
		return "-";
	end
	local hours = floor(seconds / 3600);
	local minutes = floor(mod(seconds, 3600) / 60);
	if ( hours > 0 ) then
		return hours.."h "..minutes.."m";
	end
	return minutes.."m";
end

local function SetStatRow(index, label, value)
	getglobal("BonkHeroStat"..index.."Label"):SetText(label);
	getglobal("BonkHeroStat"..index.."Value"):SetText(value);
end

function BonkHero_UpdateRecord(hero)
	local stats = HeroStats(hero) or {};
	local runs = stats.runs or 0;

	SetStatRow(1, "Runs", runs);
	SetStatRow(2, "Time played", FormatPlayed(stats.played));
	SetStatRow(3, "Best stage", stats.bestStage or "-");
	SetStatRow(4, "Longest run", stats.bestTime and FormatTime(stats.bestTime) or "-");
	SetStatRow(5, "Enemies slain", stats.kills or 0);
	SetStatRow(6, "Gold earned", FormatGold(stats.goldEarned));
	if ( stats.items and stats.items > 0 ) then
		SetStatRow(7, "Gear", stats.items.." items, item level "..(stats.itemLevel or 0));
	else
		SetStatRow(7, "Gear", "-");
	end
	SetStatRow(8, "Gear value", FormatGold(stats.gearValue));

	if ( not HeroStats(hero) ) then
		BonkHeroRecordNote:SetText("The record updates when "..hero.name.." logs out.");
	elseif ( runs == 0 ) then
		BonkHeroRecordNote:SetText(hero.name.." has not done a run yet.");
	else
		BonkHeroRecordNote:SetText("");
	end
end

function BonkHero_UpdateScene()
	if ( not Bonk.listLoaded or Bonk.creating or Bonk.wiping ) then
		return;
	end

	local hero = CurrentHero();
	if ( hero ) then
		if ( Bonk.screen ~= "charselect" ) then
			Bonk.reuseList = true;
			SetGlueScreen("charselect");
			CharacterSelect_SelectCharacter(hero.index, 1);
		elseif ( CharacterSelect.selectedIndex ~= hero.index ) then
			CharacterSelect_SelectCharacter(hero.index, 1);
		end
	elseif ( Bonk.screen ~= "charcreate" ) then
		SetGlueScreen("charcreate");
	else
		BonkHero_ApplyNewHero();
	end
end

function BonkHero_ApplyNewHero()
	if ( CurrentHero() ) then
		return;
	end
	local class = CurrentClass();
	local race = NewHeroRace();

	local races = { GetAvailableRaces() };
	local raceId;
	for i = 1, getn(races) / 2 do
		if ( strupper(races[i * 2]) == race ) then
			raceId = i;
		end
	end
	if ( not raceId ) then
		return;
	end

	if ( Bonk.appliedRace ~= race ) then
		Bonk.appliedRace = race;
		SetSelectedRace(raceId);
		SetCharacterRace(raceId);
	end
	if ( GetSelectedSex() ~= Bonk.sex ) then
		SetCharacterGender(Bonk.sex);
	end

	local classes = { GetClassesForRace() };
	for i = 1, getn(classes) / 2 do
		if ( strupper(classes[i * 2]) == class.token ) then
			SetSelectedClass(i);
			SetCharacterClass(i);
		end
	end
	BonkHero_UpdateCustomization();
end

function BonkHero_UpdateCustomization()
	local hair = GetHairCustomization();
	BonkHeroLook3Text:SetText(getglobal("HAIR_"..hair.."_STYLE"));
	BonkHeroLook4Text:SetText(getglobal("HAIR_"..hair.."_COLOR"));
	local facialHair = GetFacialHairCustomization();
	if ( facialHair == "NONE" ) then
		BonkHeroLook5:Hide();
	else
		BonkHeroLook5Text:SetText(getglobal("FACIAL_HAIR_"..facialHair));
		BonkHeroLook5:Show();
	end
end

function BonkHero_SelectClass(index)
	local class = BONK_CLASSES[index];
	if ( not IsSelectable(class) ) then
		PlaySound("igMainMenuOptionCheckBoxOff");
		BonkHero_SetStatus("The "..class.name.." is not available yet.");
		BonkHero_UpdateRoster();
		return;
	end
	PlaySound("gsCharacterCreationClass");
	if ( not Bonk.creating and not Bonk.wiping and index ~= Bonk.classIndex ) then
		Bonk.classIndex = index;
		Bonk.raceIndex = 1;
		BonkHero_SetStatus("");
	end
	BonkHero_Refresh();
end

function BonkHero_SelectRace(index)
	PlaySound("gsCharacterCreationClass");
	if ( not Bonk.creating ) then
		Bonk.raceIndex = index;
		BonkHero_SetStatus("");
	end
	BonkHero_Refresh();
end

function BonkHero_SelectSex(sex)
	PlaySound("gsCharacterCreationClass");
	if ( not Bonk.creating and not Bonk.wiping ) then
		Bonk.sex = sex;
	end
	BonkHero_Refresh();
end

function BonkHero_Randomize()
	PlaySound("gsCharacterCreationLook");
	if ( Bonk.screen == "charcreate" ) then
		RandomizeCharCustomization();
	end
end

function BonkHero_CreateCharacter()
	PlaySound("gsCharacterCreationCreateChar");
	CreateCharacter(BonkHeroNameEdit:GetText());
end

function BonkHero_EnterWorld(hero)
	BonkHero_SetStatus("Entering the world...");
	CharacterSelect_SelectCharacter(hero.index, 1);
	PlaySound("gsCharacterSelectionEnterWorld");
	EnterWorld();
end

function BonkHero_Play()
	if ( Bonk.creating or Bonk.wiping or not Bonk.listLoaded ) then
		return;
	end

	local hero = CurrentHero();
	if ( hero ) then
		BonkHero_EnterWorld(hero);
		return;
	end

	if ( GetNumCharacters() >= MAX_CHARACTERS_PER_REALM ) then
		BonkHero_SetStatus("No room for another hero. Retire one first.");
		return;
	end
	if ( Bonk.screen ~= "charcreate" ) then
		return;
	end
	if ( BonkHeroNameEdit:GetText() == "" ) then
		BonkHero_SetStatus(CHAR_NAME_NO_NAME);
		BonkHeroNameEdit:SetFocus();
		return;
	end

	BonkHeroNameEdit:ClearFocus();
	Bonk.creating = { class = CurrentClass().token };
	BonkHero_SetStatus("Creating your hero...");
	if ( Bonk.ironman ) then
		Bonk.creating.ironmanSent = true;
		CreateCharacter(IRONMAN_NAME);
		return;
	end
	BonkHero_CreateCharacter();
end

function BonkHero_Retire()
	local hero = CurrentHero();
	if ( not hero or Bonk.creating or Bonk.wiping ) then
		return;
	end
	PlaySound("gsCharacterSelectionDelCharacter");
	GlueDialog_Show("BONK_RETIRE", format("Retire %s, your %s?\nThis permanently deletes the hero and their gear. Your gold stays on the account.",
		hero.name, CurrentClass().name), hero.index);
end

BONK_WIPE_GAP = 0.3;
local WIPE_NAME = "Wipeaccount";
local WIPE_ASK_AGAIN = 3;
local WIPE_TIMEOUT = 15;

function BonkHero_Wipe()
	if ( Bonk.creating or Bonk.wiping or not Bonk.listLoaded ) then
		return;
	end
	PlaySound("gsCharacterSelectionDelCharacter");
	GlueDialog_Show("BONK_WIPE");
end

function BonkHero_StartWipe()
	Bonk.wiping = { step = "delete", wait = 0 };
	BonkHeroNameEdit:ClearFocus();
	BonkHero_SetStatus("Wiping the account...");
end

function BonkHero_StopWipe(text)
	Bonk.wiping = nil;
	BonkHero_SetStatus(text);
	BonkHero_Refresh();
end

function BonkHero_FinishWipe()
	Bonk.wiping = nil;
	BONK_STATS = { gold = 0, lastHero = "", heroes = {} };
	BonkHeroGold:SetText(FormatGold(0));
	BonkHeroGoldFrame:Show();
	Bonk.classIndex = 1;
	Bonk.raceIndex = 1;
	BonkHeroNameEdit:SetText("");
	BonkHero_Refresh();
	BonkHero_SetStatus("|cff20ff20Account wiped.|r Every hero and all progress are gone.");
end

function BonkHero_UpdateWipe(elapsed)
	local wipe = Bonk.wiping;
	if ( wipe.sent ) then
		wipe.sentFor = wipe.sentFor + elapsed;
		if ( wipe.sent == "delete" and not wipe.askedAgain and wipe.sentFor > WIPE_ASK_AGAIN ) then
			wipe.askedAgain = true;
			GetCharacterListUpdate();
		elseif ( wipe.sentFor > WIPE_TIMEOUT ) then
			BonkHero_StopWipe("The server didn't answer, so the account was not wiped.");
		end
		return;
	end
	wipe.wait = wipe.wait - elapsed;
	if ( wipe.wait > 0 ) then
		return;
	end

	local count = GetNumCharacters();
	if ( count > 0 ) then
		if ( count == 1 ) then
			BonkHero_SetStatus("Wiping the account... 1 hero left");
		else
			BonkHero_SetStatus("Wiping the account... "..count.." heroes left");
		end
		wipe.sent = "delete";
		wipe.sentFor = 0;
		wipe.askedAgain = nil;
		DeleteCharacter(1);
		return;
	end

	if ( Bonk.screen ~= "charcreate" ) then
		SetGlueScreen("charcreate");
		wipe.wait = BONK_WIPE_GAP;
		return;
	end
	BonkHero_SetStatus("Wiping the account...");
	wipe.step = "create";
	wipe.sent = "create";
	wipe.sentFor = 0;
	CreateCharacter(WIPE_NAME);
end

function BonkHero_Quit()
	PlaySound("gsTitleQuit");
	GlueDialog_Show("BONK_QUIT");
end

function BonkHero_StepClass(direction)
	local count = getn(BONK_CLASSES);
	local index = Bonk.classIndex;
	for step = 1, count do
		index = mod(index - 1 + direction + count, count) + 1;
		if ( IsSelectable(BONK_CLASSES[index]) ) then
			BonkHero_SelectClass(index);
			return;
		end
	end
end

function BonkHero_OnKeyDown()
	if ( arg1 == "ESCAPE" ) then
		BonkHero_Quit();
	elseif ( arg1 == "ENTER" ) then
		BonkHero_Play();
	elseif ( arg1 == "LEFT" ) then
		BonkHero_StepClass(-1);
	elseif ( arg1 == "RIGHT" ) then
		BonkHero_StepClass(1);
	elseif ( (arg1 == "UP" or arg1 == "DOWN") and not CurrentHero() ) then
		local count = getn(CurrentClass().races);
		if ( arg1 == "UP" ) then
			BonkHero_SelectRace(mod(Bonk.raceIndex - 2 + count, count) + 1);
		else
			BonkHero_SelectRace(mod(Bonk.raceIndex, count) + 1);
		end
	elseif ( arg1 == "PRINTSCREEN" ) then
		Screenshot();
	end
end

function BonkHero_OnMouseDown(button)
	if ( Bonk.screen == "charcreate" ) then
		CharacterCreateFrame_OnMouseDown(button);
	else
		CharacterSelectFrame_OnMouseDown(button);
	end
end

function BonkHero_OnMouseUp(button)
	CharacterCreateFrame_OnMouseUp(button);
	CharacterSelectFrame_OnMouseUp(button);
end

function BonkHero_OnUpdate(elapsed)
	if ( Bonk.wiping ) then
		BonkHero_UpdateWipe(elapsed or 0);
	end
	if ( Bonk.sceneDelay > 0 ) then
		Bonk.sceneDelay = Bonk.sceneDelay - (elapsed or 0);
	elseif ( Bonk.sceneDirty and (Bonk.screen == "charselect" or Bonk.screen == "charcreate") ) then
		Bonk.sceneDirty = false;
		BonkHero_UpdateScene();
	end

	if ( Bonk.screen == "charcreate" ) then
		CharacterCreateFrame_OnUpdate();
	else
		CharacterSelectFrame_OnUpdate();
	end
end
