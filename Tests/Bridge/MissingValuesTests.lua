local value, low, high = nil, nil, nil
local writes = 0
local photo = {getDevelopSettings=function()return {} end}
ProgramPreferences = {Limits={},ClientShowBezelOnChange=false}
MIDI2LR={PARAM_OBSERVER={},SERVER={send=function()end}}
function LOC(s)return s end
local modules = {
 LrApplication={activeCatalog=function()return {getTargetPhoto=function()return photo end} end},
 LrApplicationView={getCurrentModuleName=function()return 'develop' end},
 LrDevelopController={getValue=function()return value end,getRange=function()return low,high end,setValue=function()writes=writes+1 end,getSelectedMask=function()return nil end},
 LrTasks={startAsyncTask=function()end},
}
function import(name)return modules[name] or {} end
package.preload.Database=function()return {CmdTrans={},LatestPVSupported=1,Parameters={}} end
local limits=dofile('Packaging/PanaLux Bridge.lrplugin/Limits.lua')
assert(limits.LRValueToMIDIValue('local_Exposure')==nil)
assert(limits.MIDIValueToLRValue('local_Exposure',0.5)==nil)
limits.ClampValue('local_Exposure');assert(writes==0)
low=-5;high=5
assert(limits.LRValueToMIDIValue('local_Exposure')==nil,'missing mask must not become zero')
value=0;assert(limits.LRValueToMIDIValue('local_Exposure')==0.5)
assert(limits.MIDIValueToLRValue('local_Exposure',0.6)==1)
low=1;high=1;assert(limits.LRValueToMIDIValue('local_Exposure')==nil)
low=-5;high=5
limits.Fine(2,true);assert(limits.GetMinMax('local_Exposure')~=nil)
value=nil;assert(limits.GetMinMax('local_Exposure')==nil,'cached fine range must tolerate mask disappearing')
assert(limits.LRValueToMIDIValue('local_Exposure')==nil)
print('PASS: missing mask/value/range, zero-width range, fine-range disappearance; valid values unchanged')
