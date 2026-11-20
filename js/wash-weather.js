// 세차하기 좋은 날 — 10일 달력 상자 (홈, 지역 페이지)
// 필요: js/ww-regions.js → js/ww-core.js → 이 파일
// - <section id="washWeather"> 안에 그림. data-region="부산 해운대구" 가 있으면 그 지역으로 고정(고르는 칸 숨김)
// - 판정 기준은 ww-core.js 맨 위 설명 참고
(function () {
  const box = document.getElementById('washWeather');
  if (!box) return;
  // 지역 페이지인데 날씨 도구를 못 불렀거나, 좌표 목록에 없는 새 지역이면 상자를 숨김
  if (!window.WW || !WW.regions.length || (box.dataset.region && !WW.find(box.dataset.region))) { if (box.dataset.region) box.hidden = true; return; }

  const R = WW.regions, WD = WW.WD;
  const $ = id => box.querySelector('#' + id);
  const sido = $('wwSido'), sgg = $('wwSgg'), gps = $('wwGps'), grid = $('wwGrid'), sum = $('wwSum'), dust = $('wwDust'), where = $('wwWhere');
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const fixed = box.dataset.region ? WW.find(box.dataset.region) : null;

  // ── 지역 고르기 ──
  const top = n => n.split(' ')[0];
  if (fixed) {
    const loc = box.querySelector('.ww-loc'); if (loc) loc.hidden = true;
  } else {
    const sidos = [...new Set(R.map(r => top(r[0])))];
    sido.innerHTML = sidos.map(s => `<option>${esc(s)}</option>`).join('');
    sido.addEventListener('change', () => { fillSgg(sido.value); setRegion(sgg.value, false); });
    sgg.addEventListener('change', () => setRegion(sgg.value, false));
    gps.addEventListener('click', () => {
      if (!navigator.geolocation) return alert('이 브라우저는 위치 찾기를 지원하지 않아요. 지역을 직접 골라 주세요');
      gps.disabled = true; gps.textContent = '찾는 중…';
      navigator.geolocation.getCurrentPosition(p => {
        gps.disabled = false; gps.textContent = '📍 내 위치';
        setRegion(WW.nearest(p.coords.latitude, p.coords.longitude)[0], true);
      }, () => {
        gps.disabled = false; gps.textContent = '📍 내 위치';
        alert('위치를 알 수 없어요. 지역을 직접 골라 주세요');
      }, { timeout: 10000, maximumAge: 600000 });
    });
  }
  function fillSgg(s, pick) {
    const list = R.filter(r => top(r[0]) === s);
    sgg.innerHTML = list.map(r => `<option value="${esc(r[0])}">${esc(r[0].split(' ').slice(1).join(' ') || r[0])}</option>`).join('');
    sgg.hidden = list.length === 1;
    if (pick) sgg.value = pick;
  }
  function setRegion(name, viaGps) {
    const r = WW.find(name) || WW.find('서울 중구');
    sido.value = top(r[0]); fillSgg(top(r[0]), r[0]);
    WW.saveRegion(r[0], viaGps);
    where.textContent = viaGps ? '📍 내 위치 기준' : '';
    show(r);
  }

  function draw(d) {
    const days = d.time.slice(0, 10);   // 10일 (기상청 중기예보도 10일까지라 나중에 바꿔도 같은 모양)
    const lead = new Date(days[0] + 'T00:00:00+09:00').getDay();   // 달력처럼 일요일부터
    let h = WD.map((w, i) => `<div class="ww-wd${i === 0 ? ' sun' : i === 6 ? ' sat' : ''}">${w}</div>`).join('');
    for (let i = 0; i < lead; i++) h += '<div class="ww-day empty"></div>';
    let firstGood = -1;
    const js = days.map((t, i) => WW.judge(d, i));
    days.forEach((t, i) => {
      const dt = new Date(t + 'T00:00:00+09:00'), j = js[i];
      if (j.k === 'good' && firstGood < 0) firstGood = i;
      const label = i === 0 ? '오늘' : dt.getDate() === 1 ? (dt.getMonth() + 1) + '/1' : dt.getDate();
      h += `<div class="ww-day ${j.k}${i === 0 ? ' today' : ''}">
        <div class="ww-date">${label}</div><div class="ww-ic">${j.icon}</div>
        <div class="ww-t">${j.t}</div><div class="ww-p">${j.s}</div>
        <div class="ww-tp"><i class="ww-lo">${Math.round(d.temperature_2m_min[i])}</i><span class="sl">/</span><i class="ww-hi">${Math.round(d.temperature_2m_max[i])}</i></div></div>`;
    });
    grid.innerHTML = h;
    const t0 = js[0];
    if (t0.k === 'good') sum.innerHTML = '<b class="g">오늘 세차하기 딱 좋아요!</b> 앞으로 7일 동안 비 소식이 없어요';
    else if (firstGood > 0) sum.innerHTML = `다음 추천일: <b class="g">${WW.md(days[firstGood])}</b>`
      + (t0.gap ? `<br>오늘 세차하면 ${t0.gap}일 뒤 비 소식이 있어요` : t0.k === 'rain' ? '<br>오늘은 비 소식이 있어요' : '');
    else sum.innerHTML = '열흘 안에 7일 내내 맑은 날이 없어요. <b>보통</b>인 날을 노려 보세요';
  }

  // 미세먼지 (환경부 등급, 낮 시간 07~20시 평균)
  const G10 = [[30, '좋음', 'ww-g1'], [80, '보통', 'ww-g2'], [150, '나쁨', 'ww-g3'], [Infinity, '매우 나쁨', 'ww-g4']];
  const G25 = [[15, '좋음', 'ww-g1'], [35, '보통', 'ww-g2'], [75, '나쁨', 'ww-g3'], [Infinity, '매우 나쁨', 'ww-g4']];
  const grade = (v, G) => G.find(g => v <= g[0]);
  function drawDust(a) {
    if (!a) { dust.innerHTML = ''; return; }
    const out = [];
    [0, 1].forEach(day => {
      const ymd = (a.time[day * 24] || '').slice(0, 10);
      const idx = a.time.map((t, i) => [t, i]).filter(([t]) => { const h = +t.slice(11, 13); return t.slice(0, 10) === ymd && h >= 7 && h <= 20; }).map(x => x[1]);
      const avg = arr => { const v = idx.map(i => arr[i]).filter(x => x != null); return v.length ? v.reduce((s, x) => s + x, 0) / v.length : null; };
      const p10 = avg(a.pm10), p25 = avg(a.pm2_5);
      if (p10 == null || p25 == null) return;
      const g10 = grade(p10, G10), g25 = grade(p25, G25);
      const worse = G10.indexOf(g10) >= G25.indexOf(g25) ? g10 : g25;   // 둘 중 나쁜 쪽으로 한 줄 요약
      out.push(`<div class="ww-dd"><span class="ww-dl">${day ? '내일' : '오늘'}</span><b class="${worse[2]}">${worse[1]}</b>
        <small>미세 ${Math.round(p10)} · 초미세 ${Math.round(p25)}㎍/㎥</small></div>`);
    });
    dust.innerHTML = out.length ? '<div class="ww-dh">😷 미세먼지</div>' + out.join('') : '';
  }

  async function show(r) {
    grid.innerHTML = '<div class="ww-msg">날씨를 불러오는 중…</div>'; sum.textContent = ''; dust.innerHTML = '';
    const c = await WW.load(r, true);
    if (!c) {
      if (fixed) { box.hidden = true; return; }   // 지역 페이지에서는 빈 상자를 남기지 않음
      grid.innerHTML = '<div class="ww-msg">지금은 날씨를 불러오지 못했어요. 잠시 뒤 다시 열어 주세요</div>'; return;
    }
    draw(c.d); drawDust(c.a);
  }

  if (fixed) show(fixed);
  else { const s = WW.savedRegion(); setRegion(s ? s[0] : '서울 중구', WW.viaGps()); }
})();
