-- Runner prepends the actual PointCurveUpDown function from ClientUtilities.lua.
local writes, bezels, hdr, mode, photo, failWrite = {}, {}, false, 'develop', {}, false
LrApplicationView={getCurrentModuleName=function()return mode end}
LrApplication={activeCatalog=function()return {getTargetPhoto=function()return photo end} end}
LrTasks={pcall=pcall}
LrDialogs={showBezel=function(s)bezels[#bezels+1]=s end}
ProgramPreferences={ClientShowBezelOnChange=false}
function getValue(key) if key=='HDREditMode' then return hdr end return {0,0,255,255} end
function setValue(key,points) if failWrite then error('unsupported context') end writes[#writes+1]={key,points} end
function fChangePanel()end
package.path='Packaging/PanaLux Bridge.lrplugin/?.lua;'..package.path
local fire=PointCurveUpDown(true,true)
fire();assert(#writes==1 and writes[1][1]=='ToneCurvePV2012' and writes[1][2][2]==5)
for _,value in ipairs({true,1,'unknown'}) do hdr=value;fire();assert(#writes==1) end
hdr=nil;fire();assert(#writes==1)
hdr=false;mode='library';fire();assert(#writes==1)
mode='develop';photo=nil;fire();assert(#writes==1)
photo={};failWrite=true;fire();assert(#writes==1 and #bezels>=5)
print('PASS: actual wrapper applies SDR only, rejects HDR/unknown/no photo/wrong module, catches unavailable writes')
