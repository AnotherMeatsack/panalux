local tasks, messages, writes, order = {}, {}, {}, {}
local photo = {localIdentifier=42}
local selected = photo
local values = {Exposure=0, Contrast=0}
MIDI2LR={PARAM_OBSERVER={},SERVER={send=function(_,s) messages[#messages+1]=s;order[#order+1]='ack' end}}
local modules = {
 LrApplication={activeCatalog=function() return {getTargetPhoto=function()return selected end,getPath=function()return 'Catalog.lrcat' end} end},
 LrApplicationView={getCurrentModuleName=function()return 'develop' end},
 LrPathUtils={leafName=function(s)return s end,removeExtension=function()return 'Catalog' end},
 LrDevelopController={getValue=function(n)return values[n] end,setValue=function(n,v)values[n]=v;writes[#writes+1]={n,v};order[#order+1]='write' end},
 LrTasks={startAsyncTask=function(f)tasks[#tasks+1]=f end,pcall=pcall,sleep=function()order[#order+1]='yield' end},
}
function import(n)return modules[n] or {} end
package.preload.serpent=function()return {} end
package.preload.Database=function()return {Parameters={Exposure=true,Contrast=true,local_Exposure=true}} end
package.preload.Limits=function()return {MIDIValueToLRValue=function(_,v)return v*10-5 end} end
local rewind=dofile('Packaging/PanaLux Bridge.lrplugin/PanaLuxRewind.lua')
rewind.Preview('a Catalog:42 Exposure=0.25,Contrast=0.75,local_Exposure=0.5')
assert(#tasks==1 and #writes==0,'receiving must not block the socket callback')
tasks[1]()
assert(values.Exposure==-2.5 and values.Contrast==2.5,'whole preview applied before release')
assert(#writes==2,'missing local mask skipped')
assert(order[#order-1]=='yield' and order[#order]=='ack','render yield precedes acknowledgement')
assert(messages[1]:match('a 2 ok'))
rewind.Preview('b Catalog:42 Exposure=0.1')
rewind.Preview('c Catalog:42 Exposure=0.9')
assert(#tasks==2,'one task handles a burst')
tasks[2]();assert(values.Exposure==4,'latest pending frame replaces stale work')
rewind.Preview('d Catalog:42 Exposure=0')
selected={localIdentifier=99};tasks[3]()
assert(values.Exposure==4,'changing photos prevents stale frame application')
assert(messages[3]:match('d 0 ok'))
print('PASS: live grouped preview, render yield, acknowledgement, latest-frame coalescing, missing mask, photo identity guard')
