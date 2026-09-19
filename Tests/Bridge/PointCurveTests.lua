local adjust=dofile('Packaging/PanaLux Bridge.lrplugin/PanaLuxPointCurve.lua').adjust
local function near(a,b) assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b)) end
local points={0,0,128,128,255,255}
local raised=assert(adjust(points,true,true));near(raised[2],5);near(raised[6],255);assert(raised[4]>128);near(points[2],0)
local lowered=assert(adjust(points,false,false));near(lowered[2],0);near(lowered[6],250);assert(lowered[4]<128)
for _,curve in ipairs({{}, {0,0,255}, {0,0,0,255}, {255,255,0,0}, {0,0,256,255}, {0,0,255,300}, {0,0,255,0/0}, {0,255,255,255}}) do
 assert(adjust(curve,true,true)==nil,'must reject unsupported curve')
end
assert(adjust(nil,true,true)==nil)
assert(adjust({0,0,255,0},false,false)==nil)
for _,blacks in ipairs({true,false}) do
 for _,up in ipairs({true,false}) do
  for k=0,255,17 do
   local r=adjust({0,k,64,220,192,30,255,255-k},blacks,up)
   if r then
    for i=1,#r do assert(r[i]==r[i] and r[i]>=0 and r[i]<=255) end
    near(r[1],0);near(r[3],64);near(r[5],192);near(r[7],255)
   end
  end
 end
end
print('PASS: endpoint direction, opposite anchor, input immutability, nonmonotonic curves, bounds, malformed/HDR/degenerate rejection')
