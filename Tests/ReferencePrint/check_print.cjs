// Generated-artifact QA in an isolated headless browser. Run ReferenceImageTests first.
const { chromium } = require('playwright');
const fs = require('node:fs');
const assert = require('node:assert/strict');
(async () => {
 const browser=await chromium.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true});
 try {
  const page=await browser.newPage({viewport:{width:1440,height:1000},acceptDownloads:true});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.setContent(fs.readFileSync('/tmp/panalux-detailed-reference.html','utf8'));
  const counts=await page.locator('.diagram').evaluateAll(ds=>ds.map(d=>d.querySelectorAll('[data-ref]').length));
  assert(counts.length>10);assert(counts.every(n=>n===58),JSON.stringify(counts));
  for(const size of [{width:1200,height:800},{width:800,height:600}]){
   await page.setViewportSize(size);
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
  }
  await page.setViewportSize({width:1440,height:1000});
  await page.screenshot({path:'/tmp/panalux-svg-overview.png',fullPage:true});
  await page.locator('#holds').click();
  await page.locator('.state.selected .holds [data-ref="PREV_STILL"]').click();
  assert((await page.locator('#details').textContent()).includes('Prev Still'));
  await page.screenshot({path:'/tmp/panalux-svg-holds.png',fullPage:true});
  await page.locator('#zoom').selectOption('right');
  await page.screenshot({path:'/tmp/panalux-svg-right-keys.png',fullPage:true});
  const downloadPromise=page.waitForEvent('download');await page.locator('#savepng').click();
  await (await downloadPromise).saveAs('/tmp/panalux-svg-export.png');
  await page.evaluate(()=>{window.print=()=>{};printGuide(true)});
  await page.pdf({path:'/tmp/panalux-svg-complete.pdf',printBackground:true,preferCSSPageSize:true});
  await page.evaluate(()=>{gesture('taps');printDetails()});
  await page.pdf({path:'/tmp/panalux-svg-enlarged.pdf',printBackground:true,preferCSSPageSize:true});
  assert.deepEqual(errors,[]);
  console.log(JSON.stringify({diagrams:counts.length,controlsPerDiagram:58,print:'complete + 5 enlarged regions',png:fs.statSync('/tmp/panalux-svg-export.png').size}));
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
