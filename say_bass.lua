-- Say Bass
-- hum a bassline. lock it. loop it. build a song.
--
-- ENC1: tempo (BPM)
-- ENC2: loop length (bars)
-- ENC3: select loop slot
-- KEY1: toggle play all loops (song mode)
-- KEY2: arm / start recording  (press again to cancel)
-- KEY3: clear selected loop

engine.name = "None"

-- ─────────────────────────────────────────────
-- CONSTANTS
-- ─────────────────────────────────────────────
local MAX_LOOPS       = 8
local TICKS_PER_BEAT  = 24
local MIDI_CH         = 1
local BASS_LO         = 36   -- C2
local BASS_HI         = 60   -- C4

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

local SCALES = {
  { name="Major",      steps={0,2,4,5,7,9,11} },
  { name="Minor",      steps={0,2,3,5,7,8,10} },
  { name="Dorian",     steps={0,2,3,5,7,9,10} },
  { name="Phrygian",   steps={0,1,3,5,7,8,10} },
  { name="Mixolydian", steps={0,2,4,5,7,9,10} },
  { name="Pentatonic", steps={0,2,4,7,9}       },
  { name="Blues",      steps={0,3,5,6,7,10}    },
}

-- ─────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────
local bpm           = 90
local loop_bars     = 2
local selected      = 1
local recording     = false
local armed         = false
local playing       = false

local global_tick   = 0
local rec_start     = 0
local active_note   = -1
local loop_play_tick= 0

local scale_root    = nil
local scale_name    = nil
local scale_notes   = nil
local pitch_buf     = {}   -- rolling pitch-class history
local detected_hz   = 0

local current_rec   = {}   -- {tick, note, vel} being recorded
local loops         = {}
for i = 1,MAX_LOOPS do
  loops[i] = { events={}, length=0, filled=false, active=false }
end

local clock_id      = nil
local midi_out      = nil
local screen_dirty  = true
local splash        = true

-- ─────────────────────────────────────────────
-- MIDI HELPERS
-- ─────────────────────────────────────────────
local function note_on(n,v)
  if midi_out then midi_out:note_on(n, v or 90, MIDI_CH) end
end
local function note_off(n)
  if midi_out then midi_out:note_off(n, 0, MIDI_CH) end
end
local function all_notes_off()
  for n = BASS_LO, BASS_HI do note_off(n) end
end

-- ─────────────────────────────────────────────
-- SCALE / PITCH HELPERS
-- ─────────────────────────────────────────────
local function hz_to_midi(hz)
  if hz < 20 then return nil end
  return 69 + 12 * math.log(hz/440) / math.log(2)
end

local function build_scale(root_pc, steps)
  local t = {}
  for oct = 1,7 do
    for _,s in ipairs(steps) do
      local n = (oct+1)*12 + root_pc + s
      if n >= BASS_LO-12 and n <= BASS_HI+12 then
        t[#t+1] = n
      end
    end
  end
  table.sort(t)
  return t
end

local function snap_to_scale(mf)
  if not scale_notes then return math.floor(mf+0.5) end
  local best, dist = scale_notes[1], 999
  for _,n in ipairs(scale_notes) do
    local d = math.abs(n-mf)
    if d < dist then dist=d; best=n end
  end
  return best
end

local function detect_scale(pcs)
  local cnt = {}
  for i=0,11 do cnt[i]=0 end
  for _,pc in ipairs(pcs) do cnt[pc%12] = cnt[pc%12]+1 end
  local bscore, broot, bsc = -1, 0, SCALES[1]
  for root=0,11 do
    for _,sc in ipairs(SCALES) do
      local score=0
      for _,step in ipairs(sc.steps) do score=score+cnt[(root+step)%12] end
      if score > bscore then bscore=score; broot=root; bsc=sc end
    end
  end
  return broot, bsc
end

-- ─────────────────────────────────────────────
-- LOOP HELPERS
-- ─────────────────────────────────────────────
local function ticks_per_loop()
  return TICKS_PER_BEAT * 4 * loop_bars
end

local function finish_recording()
  recording = false
  if active_note >= 0 then
    current_rec[#current_rec+1] = {tick=ticks_per_loop(), note=active_note, vel=0}
    note_off(active_note)
    active_note = -1
  end
  local lp = loops[selected]
  lp.events = current_rec
  lp.length = ticks_per_loop()
  lp.filled = true
  lp.active = true
  current_rec = {}
  if selected < MAX_LOOPS then selected = selected+1 end
  screen_dirty = true
end

-- ─────────────────────────────────────────────
-- PITCH POLL
-- ─────────────────────────────────────────────
local function process_pitch(hz, rel_tick)
  if hz < 40 then
    if active_note >= 0 then
      if recording then current_rec[#current_rec+1]={tick=rel_tick,note=active_note,vel=0} end
      note_off(active_note)
      active_note = -1
    end
    return
  end

  detected_hz = hz
  local mf = hz_to_midi(hz)
  if not mf then return end

  pitch_buf[#pitch_buf+1] = math.floor(mf+0.5) % 12
  if #pitch_buf > 60 then table.remove(pitch_buf,1) end

  if not scale_root and #pitch_buf >= 10 then
    local r,sc = detect_scale(pitch_buf)
    scale_root  = r
    scale_name  = sc.name
    scale_notes = build_scale(r, sc.steps)
    screen_dirty = true
  end

  local snapped = snap_to_scale(mf)
  while snapped > BASS_HI do snapped = snapped-12 end
  while snapped < BASS_LO do snapped = snapped+12 end

  if snapped ~= active_note then
    if active_note >= 0 then
      if recording then current_rec[#current_rec+1]={tick=rel_tick,note=active_note,vel=0} end
      note_off(active_note)
    end
    active_note = snapped
    if recording then current_rec[#current_rec+1]={tick=rel_tick,note=snapped,vel=90} end
    note_on(snapped, 90)
  end
end

-- ─────────────────────────────────────────────
-- CLOCK TICK
-- ─────────────────────────────────────────────
local function on_tick()
  if midi_out then midi_out:clock() end
  if splash then return end

  global_tick = global_tick + 1

  if armed and (global_tick % TICKS_PER_BEAT == 0) then
    armed       = false
    recording   = true
    rec_start   = global_tick
    current_rec = {}
    screen_dirty = true
  end

  if recording then
    local rel = global_tick - rec_start
    if rel >= ticks_per_loop() then
      finish_recording()
    end
  end

  if playing then
    loop_play_tick = loop_play_tick + 1
    for i=1,MAX_LOOPS do
      local lp = loops[i]
      if lp.filled and lp.active then
        local pos = loop_play_tick % lp.length
        for _,ev in ipairs(lp.events) do
          if ev.tick == pos then
            if ev.vel > 0 then note_on(ev.note, ev.vel)
            else note_off(ev.note) end
          end
        end
      end
    end
  end

  screen_dirty = true
end

-- ─────────────────────────────────────────────
-- SCREEN
-- ─────────────────────────────────────────────
local function draw_splash()
  screen.clear()
  screen.aa(1)
  local cx = 64
  local n_top = 6
  local tw, th = 9, 13
  local gw = n_top*tw + 6
  local gy_top = 18
  screen.level(11)
  screen.rect(cx-gw/2, gy_top-6, gw, 7)
  screen.fill()
  for i=0, n_top-1 do
    local x = cx - gw/2 + 3 + i*tw
    screen.level(15)
    screen.rect(x, gy_top, tw-2, th)
    screen.fill()
    screen.level(0)
    screen.rect(x + tw-2, gy_top, 1, th)
    screen.fill()
  end
  local n_bot = 5
  local gy_bot = gy_top + th + 4
  screen.level(11)
  screen.rect(cx-gw/2, gy_bot + th, gw, 7)
  screen.fill()
  for i=0, n_bot-1 do
    local x = cx - gw/2 + 8 + i*tw
    screen.level(15)
    screen.rect(x, gy_bot, tw-2, th)
    screen.fill()
    screen.level(0)
    screen.rect(x + tw-2, gy_bot, 1, th)
    screen.fill()
  end
  screen.level(15)
  screen.font_size(8)
  screen.move(64,56)
  screen.text_center("SAY BASS")
  screen.level(4)
  screen.move(64,63)
  screen.text_center("press any key")
  screen.update()
end

local function draw_main()
  screen.clear()
  screen.aa(0)
  screen.font_size(8)
  screen.level(15)
  screen.move(0,7)
  screen.text("SAY BASS")
  screen.level(6)
  screen.move(128,7)
  screen.text_right(bpm.."bpm  "..loop_bars.."bar")
  if scale_root then
    screen.level(10)
    screen.move(0,15)
    screen.text(NOTE_NAMES[scale_root+1].." "..scale_name)
  else
    screen.level(3)
    screen.move(0,15)
    screen.text("hum to detect scale")
  end
  local px = 84
  screen.level(2)
  screen.rect(px, 8, 44, 7)
  screen.fill()
  if detected_hz > 40 then
    local mf = hz_to_midi(detected_hz) or BASS_LO
    local norm = math.max(0, math.min(1, (mf-BASS_LO)/(BASS_HI-BASS_LO)))
    screen.level(11)
    screen.rect(px, 8, math.floor(norm*44), 7)
    screen.fill()
  end
  local sw, sh = 13, 10
  local sy = 22
  for i=1,MAX_LOOPS do
    local lp = loops[i]
    local bx = (i-1)*(sw+3)
    local is_sel = (i==selected)
    screen.level(is_sel and 4 or 1)
    screen.rect(bx, sy, sw, sh)
    screen.fill()
    if lp.filled then
      screen.level(lp.active and 10 or 4)
      screen.rect(bx+1, sy+1, sw-2, sh-2)
      screen.fill()
    end
    if is_sel then
      if recording then
        screen.level((global_tick//6)%2==0 and 15 or 6)
      elseif armed then
        screen.level(7)
      else
        screen.level(5)
      end
      screen.rect(bx, sy, sw, sh)
      screen.stroke()
    end
    screen.level(lp.filled and 0 or 5)
    screen.move(bx + sw/2 + 1, sy + sh - 2)
    screen.text_center(tostring(i))
  end
  local bar_y = 36
  screen.level(2)
  screen.rect(0, bar_y, 128, 4)
  screen.fill()
  if recording then
    local prog = math.min((global_tick-rec_start)/ticks_per_loop(), 1)
    screen.level(12)
    screen.rect(0, bar_y, math.floor(prog*128), 4)
    screen.fill()
  end
  local st_y = 44
  if recording then
    screen.level(15)
    screen.move(0, st_y); screen.text("REC")
  elseif armed then
    screen.level(8)
    screen.move(0, st_y); screen.text("ARMED")
  elseif playing then
    screen.level(12)
    screen.move(0, st_y); screen.text("SONG")
  else
    screen.level(4)
    screen.move(0, st_y); screen.text("STOP")
  end
  local pr_y, pr_h = 47, 12
  local lp = loops[selected]
  screen.level(1)
  screen.rect(0, pr_y, 128, pr_h)
  screen.fill()
  if lp.filled and lp.length > 0 then
    for _,ev in ipairs(lp.events) do
      if ev.vel > 0 then
        local xp = math.floor(ev.tick/lp.length * 127)
        local yn = pr_h-1 - math.floor((ev.note-BASS_LO)/(BASS_HI-BASS_LO)*(pr_h-2))
        screen.level(12)
        screen.pixel(xp, pr_y+yn)
        screen.fill()
      end
    end
  end
  screen.level(3)
  screen.move(0,63)
  screen.text("K1=play  K2=rec  K3=clr")
  screen.level(6)
  screen.move(128,63)
  screen.text_right("E1=bpm E2=bars E3=slot")
  screen.update()
end

function redraw()
  if splash then draw_splash() else draw_main() end
end

function key(n,z)
  if z ~= 1 then return end
  if splash then splash=false; screen_dirty=true; return end
  if n==1 then
    playing = not playing
    if playing then
      loop_play_tick = -1  -- start at -1 so first on_tick() increment lands on 0
      if midi_out then midi_out:start() end
    else
      all_notes_off()
      if midi_out then midi_out:stop() end
    end
  elseif n==2 then
    if recording then
      recording=false; armed=false
      current_rec={}
      if active_note>=0 then note_off(active_note); active_note=-1 end
    elseif armed then
      armed=false
    else
      armed=true
    end
  elseif n==3 then
    local lp=loops[selected]
    lp.events={}; lp.length=0; lp.filled=false; lp.active=false
    if active_note>=0 then note_off(active_note); active_note=-1 end
  end
  screen_dirty=true
end

function enc(n,d)
  if splash then return end
  if n==1 then
    bpm = util.clamp(bpm+d, 40, 220)
    params:set("clock_tempo", bpm)
  elseif n==2 then
    loop_bars = util.clamp(loop_bars+d, 1, 8)
  elseif n==3 then
    selected = util.clamp(selected+d, 1, MAX_LOOPS)
  end
  screen_dirty=true
end

function init()
  midi_out = midi.connect(1)
  local pitch_poll = poll.set("pitch_in_l", function(hz)
    local rel = recording and (global_tick - rec_start) or 0
    process_pitch(hz, rel)
    detected_hz = (hz > 40) and hz or detected_hz
    screen_dirty = true
  end)
  pitch_poll.time = 0.05
  pitch_poll:start()
  poll.set("amp_in_l", function(amp)
    if amp < 0.001 then detected_hz = 0 end
  end):start()
  params:set("clock_tempo", bpm)
  clock_id = clock.run(function()
    while true do
      clock.sync(1/TICKS_PER_BEAT)
      on_tick()
    end
  end)
  clock.run(function()
    while true do
      clock.sleep(1/30)
      if screen_dirty then redraw(); screen_dirty=false end
    end
  end)
end

function cleanup()
  if clock_id then clock.cancel(clock_id) end
  all_notes_off()
  if midi_out then midi_out:stop() end
end
