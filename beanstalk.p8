pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
game={}
level={}
level_seed=0
player={}
controller={}
replay=nil

-- current game mode
mode=nil

-- set to change mode before next update
mode_next=nil

max_charge=24
max_drop_speed=64

function _init()
	level_seed=rnd(t())
	mode_next="ply"
end

function _update()
	update_mode()
	if mode=="ply" then
		update_game()
	elseif mode=="gov" then
		update_game_over()
	elseif mode=="nxt" then
		update_level_won()
	end
end

function update_mode()
	if (not mode_next) return
	mode=mode_next
	mode_next=nil
	if (mode=="ply") start_game()
	if (mode=="gov") game_over()
	if (mode=="nxt") level_won()
end

function _draw()
	if mode=="ply" then
		draw_game()
	elseif mode=="gov" then
		draw_game()
		draw_game_over()
	elseif mode=="nxt" then
		draw_game()
		draw_level_won()
	end
end

------------
-- init game
------------

function start_game()
	game={}
	game.timer=0
	game.score=0
	game.viewport=0
	game.started=false

	init_level()
	init_player()

	controller.charge=0
	controller.jumped=false
	controller.jump_charge=0
	controller.locked=true
end

function init_level()
	srand(level_seed)

	local l={}
	-- floor
	local floor=make_platform()
	floor.kind="flr"
	floor.sprite=20
	floor.w=16
	l[1]=floor

	-- generate level
	local y=0
	local side=flr(rnd(2))*2-1
	local width_lut={6,5,4,4,3,3,2}
	local offset_lut={8,12,16,24,28,32,40,48}
	local dy_lut={32,40,48,56,64,72}
	local conveyor_dir=1
	for i=2,8 do
	-- compute width
		local w=width_lut[#width_lut]
		if (i-1<#width_lut) w=width_lut[i-1]
		if (w>2 and rnd(1)<0.5) w-=1
		if (w<6 and rnd(1)<0.5) w+=1
	-- compute offset
		local omax=offset_lut[#offset_lut]
		if (i-1<#offset_lut) omax=offset_lut[i-1]
		local op=rnd(1)
		local o=op*omax
	-- compute x
		local x=min(128-w*8,max(0,64+side*o-w*4))
		local change_side=rnd(1)<0.5
		if (change_side) side*=-1
	-- compute y
		local dy=dy_lut[#dy_lut]
		if (i-1<#dy_lut) dy=dy_lut[i-1]
		if (change_side and dy>56) dy=flr(dy*0.75)
		y+=dy
	-- compute type
		local platform=make_platform()
		platform.x=x
		platform.y=y
		platform.w=w
		local special=rnd(1)
		if special<0.4 then
			local kind=rnd(1)
			if kind<0.4 then
				platform.kind="ice"
				platform.sprite=19
			elseif kind<0.7 then
				platform.x=8
				platform.kind="mov"
				platform.sprite=25
				platform.heading=1
				platform.speed=1
			else
				platform.kind="cnv"
				platform.sprite=21
				platform.heading=conveyor_dir
				platform.speed=0.5
				config_animatable(platform,{21,21,22,22,23,23,24,24},conveyor_dir)
				conveyor_dir*=-1
			end
		end

		l[i]=platform
	end

	level.platforms=l

	local lh=l[#l].y+128
	level.height=lh

	level.objects={{x=64,y=lh-64,r=4,t="goal"}}
end

function make_platform()
	local p={}
	-- speed and heading are used in different ways for
	--  o moving platforms
	--  o conveyor platforms
	local i={x=0,y=0,w=0,kind="reg",sprite=18,heading=0,speed=0,moved=0}
	setmetatable(p,{__index=i})
	return p
end

function config_animatable(a,frames,dir)
	a.frame=1
	a.frames=frames
	a.frames_dir=dir
end

function update_animatable(a)
	local d=a.frames_dir or 1
	local n=#a.frames
	local f=a.frame+d
	if (f<1) f=n
	if (f>n) f=1
	a.frame=f
	a.sprite=a.frames[a.frame]
end

function init_player()
	player.x=64
	player.y=0 -- from bottom
	player.dx=0
	player.dy=0
	player.r=4
	player.frame=0
	player.touch=nil
	player.jumps=0
	player.dead=false
	player.history={}
end

------------
-- play game
------------

function update_game()
	if (game.started) game.timer+=1

	update_controls()
	if (not game.started and controller.jumped) game.started=true

	if game.started then
		-- build new replay
		local h=player.history
		h[#h+1]=player.y

		-- update current replay
		local r=replay
		if (r!=nil and r.index<#(r.history)) r.index+=1
	end

	update_platforms()
	update_player()
	update_camera()
	update_floor()

	if player.dead then
		mode_next="gov"
	end
end

function update_platforms()
	local platforms=level.platforms
	for plt in all(platforms) do
		if (plt.heading!=0) move_platform(plt)
		if (plt.frame!=nil) update_animatable(plt)
	end
end

function move_platform(p)
	if p.kind!="mov" then
		p.moved=0
		return
	end
	local nx=p.x+p.heading*p.speed
	local x0=8
	local x1=120-p.w*8
	if nx<x0 then
		p.x=x0
		p.heading=1
	elseif nx>x1 then
		p.x=x1
		p.heading=-1
	end
	p.moved=nx-p.x
	p.x=nx
end

function update_controls()
	local c=controller
	if c.locked then c.locked=btn(5) return end

	c.jumped=false
	c.jump_charge=0
	if btn(5) then
		c.charge=min(c.charge+1,max_charge)
	elseif c.charge>0 then
		c.jumped=true
		c.jump_charge=c.charge
		c.charge=0
	end
end

function update_player()
	local p=player
	local c=controller

	if (hit_test_objects(p) and mode_next) return

	if p.touch and c.jumped then
		jump(p,c.jump_charge)
	end

	-- speed
	update_player_dx(p,c)
	update_player_dy(p)

	-- position
	p.prev_x=p.x
	p.prev_y=p.y
	update_player_y(p)
	update_player_x(p)

	-- sprites
	update_player_spr(p,c)
end

function jump(p,charge)
	p.dx=0
	p.dy=24+(charge/max_charge)*160
	p.jumps+=1
	p.touch=nil
	p.frame=0
	sfx(0)
end

function update_player_dx(p,c)
	if p.touch then
		return
	end

	if btn(0) then
		p.dx=max(-8,p.dx-1)
	elseif btn(1) then
		p.dx=min( 8,p.dx+1)
	else
	-- degrade speed
		if (p.dx<0) p.dx+=0.5
		if (p.dx>0) p.dx-=0.5
	end
end

function update_player_dy(p)
	if p.touch then
		p.dy=0
	else
		p.dy=max(-max_drop_speed,p.dy-6)
	end
end

function update_player_y(p)
	local ny
	if p.touch then
		ny=p.y
	else
		ny=p.y+p.dy/30
	end

	if p.dy<=0 then
		local hx0=p.x-2
		local hx1=p.x+3
		local hit=hit_test(hx0,hx1,p.y,ny)
		if hit and not p.touch then
		-- land on platform
			ny=hit.y
			p.touch=hit
			if (hit.kind!="ice") p.dx=0
			p.dy=0
		elseif p.touch and not hit then
		-- drop from platform
			ny=p.y
			p.touch=nil
			p.dy=-max_drop_speed
		end
	end
	p.y=ny
end

function hit_test(x0,x1,y0,y1)
	local ps=level.platforms
	for p in all(ps) do
		if y0>=p.y and y1<=p.y then
			local px1=p.x+p.w*8
			if x1>=p.x and x0<=px1 then
			-- found hit
				return p
			end
		end
	end
	return nil
end

function hit_test_objects(p)
	local gos=level.objects

	local px=p.x-p.r
	local py=p.y
	local ps=2*p.r

	for go in all(gos) do
	-- box test
		local x=go.x-go.r
		local y=go.y-go.r
		local s=2*go.r
		if intersect_box(px,py,ps,ps,x,y,s,s) then
			player_collide(p,go)
			return true
		end
	end
	return false
end

function intersect_box(x1,y1,w1,h1,x2,y2,w2,h2)
	local ox=not(x1+w1<=x2 or x2+w2<=x1)
	local oy=not(y1+h1<=y2 or y2+h2<=y1)
	return ox and oy
end

function player_collide(p,go)
	if (go.t=="goal") mode_next="nxt"
end

function update_player_x(p)
	if p.touch then
	-- move along with the platform
		if (p.touch.kind=="mov") p.x+=p.touch.moved
	-- move into the direction of the conveyor
		if (p.touch.kind=="cnv") p.x+=p.touch.heading*p.touch.speed
	else
	-- move and wrap around
		p.x+=p.dx/8
		if (p.x<-4) p.x+=128
		if (p.x>128) p.x-=128
	end
end

function update_player_spr(p,c)
	if btn(5) then
		if c.charge==max_charge then
			p.frame=(p.frame+1)%6
			if p.frame<3 then
				p.sprite=1
			else
				p.sprite=17
			end
		elseif c.charge>16 then
			p.sprite=1
		elseif c.charge>8 then
			p.sprite=2
		else
			if p.touch then
				p.sprite=3
			else
				if p.dy<0 then
					p.sprite=5
				else
					p.sprite=4
				end
			end
		end
	else
		if p.touch then
			p.sprite=3
		elseif p.dy<0 then
			p.sprite=5
		else
			p.sprite=4
		end
	end
end

function update_camera()
	local lh=level.height
	local cy=lh-player.y-80
	-- clamp to top and bottom
	cy=max(0,min(lh-120,cy))
	game.viewport=cy
end

function update_floor()
	local floor=level.platforms[1]
	if floor.kind=="flr" then
		if game.started and player.y>128 then
			floor.kind="666"
			floor.sprite=33
		end
	else
		floor.y+=1
		if floor.y>player.y then
			player.y=floor.y
			player.dy=0
			player.dead=true
		end
	end
end

-- draw
function draw_game()
	cls()
	local g=game

	camera(0,g.viewport)

	-- draw platforms
	local h=level.height
	local platforms=level.platforms
	for p in all(platforms) do
		local y=h-p.y

		local sy=y-g.viewport
		if (sy<-7) break

		if sy<128 then
			local x=p.x
			for i=1,p.w do
				spr(p.sprite,x,y)
				x+=8
			end
		end
	end

	-- draw replay
	local r=replay
	if r!=nil then
		local y=h-r.history[r.index]
		rect(0,y,127,y-8,1)
	end

	-- draw player
	local p=player
	spr(p.sprite,p.x-4,h-p.y-8)
	spr(p.sprite,p.x-4+128,h-p.y-8)

	-- draw goal
	local goal=level.objects[1]
	spr(6,goal.x-4,h-goal.y-4)

	camera()

	-- draw timer
	local seconds=flr(g.timer/30)
	local minutes=flr(seconds/60)
	seconds=seconds-minutes*60
	local tim=""
	if (minutes<10) tim=tim.."0"
	tim=tim..minutes..":"
	if (seconds<10) tim=tim.."0"
	tim=tim..seconds
	print(tim,1,1,7)

	-- draw score
	local pts=""..g.score
	if (g.score<10000) pts="0"..pts
	if (g.score<1000) pts="0"..pts
	if (g.score<100) pts="0"..pts
	if (g.score<10) pts="0"..pts
	print(pts,108,1,7)

	-- draw minimap
	local mmx=125
	local mmy0=127-16
	local mmy1=16
	line(mmx,mmy0,mmx,mmy1,7)
	local mmh=mmy0-mmy1
	-- indicate player pos
	local mmp=mmy0-max(0,min(mmh,(p.y/h)*mmh))
	line(mmx-1,mmp,mmx+1,mmp,8)
	-- indicate floor pod
	local floor=platforms[1]
	local mmf=mmy0-max(0,min(mmh,(floor.y/h)*mmh))
	line(mmx-1,mmf,mmx+1,mmf,2)
end

------------
-- game over
------------

function game_over()
	-- restart replay
	if (replay!=nil) replay.index=1
	controller.locked=true
	blink=0
end

function update_game_over()
	blink=(blink+1)%15

	local c=controller
	if c.locked then c.locked=btn(4) or btn(5) return end
	if btnp(4) or btnp(5) then
		mode_next="ply"
	end
end

function draw_game_over()
	local message=nil
	if (blink<7) message="press button to restart"
	draw_text_box("g a m e   o v e r", message)
end

function draw_text_box(title,message)
	rectfill(0,48,127,80,0)
	line(0,48,127,48,7)
	line(0,80,127,80,7)

	print(title,64-#title*2,48+8,7)

	if message then
		print(message,64-#message*2,80-8-4,7)
	end
end

------------
-- level won
------------

function level_won()
	controller.locked=true

	if replay==nil or game.timer<#(replay.history) then
		replay={}
		replay.history=player.history
	end

	replay.index=1
	blink=0
end

function update_level_won()
	blink=(blink+1)%15

	local c=controller
	if c.locked then c.locked=btn(4) or btn(5) return end
	if btnp(4) or btnp(5) then
		mode_next="ply"
	end
end

function draw_level_won()
	local message=nil
	if (blink<7) message="press button to continue"
	draw_text_box("l e v el   w o n", message)
end

__gfx__
00000000000000000000000000000000008008009980089900cccc00000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000800008000588500997887990c0000c0000000000000000000000000000000000000000000000000000000000000000000000000
007007004000000408000080007887000078870009588590c077000d000cc0000000000000000000000000000000000000000000000000000000000000000000
000770004080080440788704095885900988889044888844c070000d00c70d000007c00000000000000000000000000000000000000000000000000000000000
000770004958859449588594948888499488884940888804c000000d00c00d00000cd00000000000000000000000000000000000000000000000000000000000
007007009478874994888849944884499448844904488440c000000d000dd0000000000000000000000000000000000000000000000000000000000000000000
0000000048888884948888490948849090444409040000400c0000d0000000000000000000000000000000000000000000000000000000000000000000000000
00000000048888400408804004400440000440000040040000dddd00000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000bbbb3333cccccccc55554444655665566655665556655665556655668aa88aa8000000000000000000000000000000000000000000000000
0000000000000000bbbb3333777777774555544411111111111111111111111111111111aa8888aa000000000000000000000000000000000000000000000000
00000000700000073333bbbb7777777744555544dddddddddddddddddddddddddddddddda888888a000000000000000000000000000000000000000000000000
0000000070700707111133337777777755511115dddddddddddddddddddddddddddddddd99222299000000000000000000000000000000000000000000000000
00000000750660570000000066666666555511112222222222222222222222222222222229922992000000000000000000000000000000000000000000000000
00000000570660750000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000766666670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000076666700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000060606060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000666666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000006d6d6d6d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000555555550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000505050500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
1212120000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1313130000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1414140000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1919190000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1515150000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2121210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000300001135014350183401b340283302b3301f3001d300260001570015700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000c0030c00300000000003c6053c6053c605000000c0030c00300000000003c60500000000003c6050c0030c00300000000003c6053c60500000000000c0030c00300000000003c605000003c6053c605
000c00000e3050e3050c3050c30511306113061030610306000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
03 01424344

