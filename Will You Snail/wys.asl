state("Will You Snail", "1.3")
{
	double chaptertime: 0x10243C0, 0x8, 0x150, 0xD50;
	double fulltime: 0x10243C0, 0x8, 0x150, 0xD60;
	bool showtimers: 0x0101CBB8, 0x0, 0xCD0, 0x18, 0x78;
}

state("Will You Snail", "1.42")
{
	// these need to be updated every patch
	// chaptertime is just 0x10 less on the last offset compared to fulltime
	// leveltime is like 0x20 less than chaptertime or something. it's around there. if you ever need it
	double chaptertime: 0x10F40E0, 0x8, 0x170, 0xF30; 
	double fulltime: 0x10F40E0, 0x8, 0x170, 0xF40;
	bool showtimers: 0x010EC8D8, 0x0, 0xD50, 0x18, 0x60;
}

startup
{
	Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Basic");
	vars.Helper.GameName = "Will You Snail?";
	vars.Helper.Settings.CreateFromXml("Components/WYS.Settings.xml");
	vars.Helper.AlertGameTime();

	// update these if they change
	vars.StartupRoom = 24;
	vars.PhotosensRoom = 16;
	vars.LevelSelect = 144;
	vars.Pause = 145;
	vars.SaveSelect = 26;
	vars.StartRoom = 29;
	vars.Frustration = 9;
	vars.Bosses = new List<int>() { 50, 71, 93, 121, 140, 141 };
	vars.ChapterStarts = new List<int>() { 29, 52, 73, 95, 123 };
	vars.ChapterEnds = new List<int>() { 51, 72, 94, 122, 142 };

	// defaults
	vars.OldRoomNotPause = -1;
	vars.CurrentRoomNotPause = -1;
}

init
{ 
	var mms = modules.First().ModuleMemorySize;
	switch (mms)
	{
		case 0x142A000: version = "1.42"; break;
		case 0x1347000: version = "1.3"; break;
		default: version = "Unknown"; break;
	}

	// https://gist.github.com/just-ero/3b07dc98802ba3652cb13ff8313bbfee
	// i posted old screenshots in the #livesplit or #memory channel ages ago going into more depth for
	// this if you really want to get into the nitty-gritty

	var mainModule = modules.First(); // "Will You Snail.exe"
	var scr = new SignatureScanner(game, mainModule.BaseAddress, mainModule.ModuleMemorySize);
	var levelTarget = new SigScanTarget(0xF, "3B 1D ?? ?? ?? ?? 7C E3 E8 ?? ?? ?? ?? 89 3D ?? ?? ?? ??");
 
	levelTarget.OnFound = (proc, scanner, address) => {
		var RIPaddr = proc.ReadValue<int>(address);
		return address + 0x4 + RIPaddr;
	};

	vars.room = scr.Scan(levelTarget);
}

update {
	// have to explicitly set the values for things that are sig-scanned
	current.room = game.ReadValue<int>((IntPtr) vars.room);

	if(old.room != current.room) print(current.room.ToString());

	// handles OldRoomNotPause
	if(old.room != current.room && current.room != vars.Pause)
	{
		vars.OldRoomNotPause = vars.CurrentRoomNotPause;
		vars.CurrentRoomNotPause = current.room;
	}

	if(old.room == current.room)
		vars.OldRoomNotPause = vars.CurrentRoomNotPause;
	
	return true;
}

isLoading
{
	return true;
}

gameTime
{
	// fairly self-explanatory
	if(settings["chapter_timer"]) {
		return TimeSpan.FromSeconds(current.chaptertime);
	} else {
		return TimeSpan.FromSeconds(current.fulltime);
	}
}

start
{
	// when in chapter mode:
	if(settings["chapter_timer"])
	{
		return old.room != current.room     // if we just entered this room
			&& current.showtimers           // and if timers are showing (so we just entered this room still, might be redundant)
			&& vars.ChapterStarts.Contains(current.room)     // and this room is the first room in a chapter
			&& current.chaptertime < 1;     // and the timer has just reset (1 is arbitrary)
	}

	// when in full-game mode:
	return current.room == vars.StartRoom           // start only if we are in the first room (29)
		&& current.fulltime != old.fulltime && old.fulltime == 0;   // and if the timer was 0 and has changed
}

split {
	// final split for chapters
	if(settings["chapter_timer"] && current.showtimers && !old.showtimers
		&& vars.ChapterEnds.Contains(current.room) // and we're at the end of a chapter
		&& old.room == current.room     // and we didn't just load this room
	) {
		return true;
	}

	// case where the unpause frames get skipped? theoretically this case shouldn't be possible
	if(current.room == vars.LevelSelect)
	{
		// if the room we were just in, not counting pause, is a boss room, and we are now in level select, split
		return vars.Bosses.Contains(vars.OldRoomNotPause);
	}

	// rooms where we shouldn't split
	if(current.room == vars.Pause
		|| current.room == vars.SaveSelect
		|| current.room == vars.StartupRoom
	) {
		return false;
	}

	string key = "room_" + old.room;
	return settings.ContainsKey(key) && settings[key] && old.room != current.room;
}

reset {
	// self-explanatory
	if(settings["reset_onsaveselect"] && current.room == vars.SaveSelect)
		return true;

	// reset when going to level select for chapter timers. You might want to make this another setting later on
	if(settings["chapter_timer"] && current.room == vars.LevelSelect && old.room != current.room)
		return !vars.Bosses.Contains(vars.OldRoomNotPause);
}

exit
{
	if(settings["reset_ongameclose"])
		vars.Helper.Timer.Reset();
}
