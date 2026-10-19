// 選手端網頁（掃 QR 後由裁判手機提供）。
const String kPlayerPage = r'''<!doctype html>
<html lang="zh-Hant"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no">
<title>百米賽跑・選手</title>
<style>
:root{--bg:#0b1220;--ink:#f1f5f9;--mute:#8aa0b8;--cy:#22d3ee;--or:#fb923c;--line:#1f2f46}
*{box-sizing:border-box}
html,body{margin:0;height:100%;background:var(--bg);color:var(--ink);font-family:system-ui,"Noto Sans TC","PingFang TC",sans-serif}
main{max-width:480px;margin:0 auto;padding:20px 18px 40px;display:flex;flex-direction:column;gap:14px}
h1{margin:0;font-size:26px}
#card{display:flex;flex-direction:column;gap:12px;background:#111c30;border:1px solid var(--line);border-radius:14px;padding:16px}
label{display:flex;flex-direction:column;gap:6px;color:var(--mute);font-size:14px}
input{font-size:18px;padding:12px;border-radius:10px;border:1px solid var(--line);background:#0b1220;color:var(--ink)}
button{font-size:18px;font-weight:700;padding:14px;border:0;border-radius:12px;background:var(--cy);color:#04222b}
button:focus-visible,input:focus-visible{outline:3px solid #fff;outline-offset:2px}
#status{font-size:18px;color:#fde68a;min-height:26px}
#lane{font-size:44px;font-weight:900;line-height:1.1}
.meter{display:grid;grid-template-columns:64px 1fr 72px;gap:10px;align-items:center;font-size:14px;color:var(--mute)}
.bar{height:16px;border-radius:8px;background:#16233a;overflow:hidden}
.bar i{display:block;height:100%;width:0;border-radius:8px}
#bg{background:var(--cy)}#bs{background:var(--or)}
.meter b{color:var(--ink);text-align:right;font-variant-numeric:tabular-nums}
p{margin:0;color:var(--mute);font-size:13px;line-height:1.6}
</style></head><body><main>
<h1>🏃 百米賽跑</h1>
<div id="card">
  <label>你的名字<input id="name" maxlength="12" placeholder="例如：小明" autocomplete="off"></label>
  <button id="go">連線並啟用感測器</button>
</div>
<div id="status">尚未連線</div>
<div id="lane"></div>
<div class="meter"><span>陀螺儀</span><div class="bar"><i id="bg"></i></div><b id="tg">0</b></div>
<div class="meter"><span>震動</span><div class="bar"><i id="bs"></i></div><b id="ts">0</b></div>
<p id="hint">連線後請保持這個頁面在前景、螢幕不要鎖定。比賽時像跑步一樣用力揮動手機。</p>
</main>
<script>
(function(){
  var $=function(id){return document.getElementById(id)};
  var ws=null,wantOpen=false,retry=0,lastSend=0,gotMotion=false;
  var gx=0,gy=0,gz=0,haveG=false,gyro=0,shake=0,wl=null;
  function store(k,v){try{if(v===undefined)return localStorage.getItem(k);localStorage.setItem(k,v)}catch(e){}return null}
  var rid=store("rid");
  if(!rid){rid=(window.crypto&&crypto.randomUUID)?crypto.randomUUID():String(Math.random()).slice(2)+Date.now();store("rid",rid)}
  $("name").value=store("name")||"";
  function say(t){$("status").textContent=t}
  var PHASE={lobby:"請揮動手機，測試靈敏度",countdown:"倒數中，準備！",racing:"跑！用力揮動手機！",finished:"比賽結束"};
  function onStatus(m){
    $("lane").textContent=m.lane<0?"觀戰中":(m.label+" 道");
    $("lane").style.color=m.lane===0?"#22d3ee":(m.lane===1?"#fb923c":"#8aa0b8");
    say(m.lane<0?"跑道已滿，等有人離開會自動遞補":(m.name+"｜"+(PHASE[m.phase]||"")));
  }
  function connect(){
    if(!wantOpen)return;
    ws=new WebSocket("wss://"+location.host+"/ws");
    ws.onopen=function(){retry=0;ws.send(JSON.stringify({t:"hello",id:rid,name:$("name").value.trim()}));say("已連線，等待裁判…")};
    ws.onmessage=function(ev){
      var m;try{m=JSON.parse(ev.data)}catch(e){return}
      if(m.t==="status")onStatus(m);
      else if(m.t==="vib"){if(navigator.vibrate)navigator.vibrate(m.p)}
      else if(m.t==="full"){wantOpen=false;say("房間已滿")}
    };
    ws.onclose=function(){ws=null;if(wantOpen){say("連線中斷，重新連線中…");setTimeout(connect,Math.min(5000,1000*(++retry)))}};
    ws.onerror=function(){};
  }
  function rd(v){return Math.round(v*10)/10}
  function onMotion(e){
    gotMotion=true;
    var r=e.rotationRate||{};
    var rx=r.beta||0,ry=r.gamma||0,rz=r.alpha||0;
    var lx=0,ly=0,lz=0,a=e.acceleration;
    if(a&&a.x!=null){lx=a.x||0;ly=a.y||0;lz=a.z||0}
    else{
      var g=e.accelerationIncludingGravity;
      if(g&&g.x!=null){
        if(!haveG){gx=g.x;gy=g.y;gz=g.z;haveG=true}
        gx=gx*0.9+g.x*0.1;gy=gy*0.9+g.y*0.1;gz=gz*0.9+g.z*0.1;
        lx=g.x-gx;ly=g.y-gy;lz=g.z-gz;
      }
    }
    gyro=Math.sqrt(rx*rx+ry*ry+rz*rz);
    shake=Math.sqrt(lx*lx+ly*ly+lz*lz);
    var now=performance.now();
    if(now-lastSend<30)return;
    lastSend=now;
    if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:"s",rx:rd(rx),ry:rd(ry),rz:rd(rz),lx:rd(lx),ly:rd(ly),lz:rd(lz)}));
  }
  function paint(){
    $("bg").style.width=Math.min(100,gyro/720*100)+"%";
    $("bs").style.width=Math.min(100,shake/30*100)+"%";
    $("tg").textContent=Math.round(gyro)+"°/s";
    $("ts").textContent=rd(shake)+" m/s²";
    requestAnimationFrame(paint);
  }
  function wake(){try{if(navigator.wakeLock)navigator.wakeLock.request("screen").then(function(l){wl=l}).catch(function(){})}catch(e){}}
  document.addEventListener("visibilitychange",function(){if(document.visibilityState==="visible"&&wantOpen)wake()});
  $("go").onclick=function(){
    store("name",$("name").value.trim());
    var ask=(window.DeviceMotionEvent&&typeof DeviceMotionEvent.requestPermission==="function")
      ?DeviceMotionEvent.requestPermission():Promise.resolve("granted");
    ask.then(function(s){
      if(s!=="granted"){say("需要允許「動作與方向」權限。請重新整理頁面再試一次。");return}
      window.addEventListener("devicemotion",onMotion);
      wantOpen=true;if(!ws)connect();
      $("card").style.display="none";
      wake();
      if(navigator.vibrate)navigator.vibrate(40);
      else $("hint").textContent+=" （這支手機的瀏覽器不支援震動回饋，不影響比賽。）";
      setTimeout(function(){
        if(!gotMotion)say(window.isSecureContext?"收不到感測器資料：請確認手機有陀螺儀，且瀏覽器允許動作感測。":"不是安全連線，感測器被封鎖：請用 https 網址開啟。");
      },2500);
    }).catch(function(e){say("感測器啟用失敗："+e)});
  };
  paint();
})();
</script></body></html>
''';
