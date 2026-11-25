// 세차하기 좋은 날 — 여러 화면이 같이 쓰는 부분 (날씨 받기·판정·가까운 지역 찾기)
// 필요: js/ww-regions.js 를 먼저 불러야 함
// - 날씨: Open-Meteo 무료 예보 (키 없음). 미세먼지: Open-Meteo 대기질 예측(CAMS)
// - 받은 예보는 지역별로 2시간 동안 휴대폰에 저장
// - 판정 (운영자 기준 2026-11-20: 세차하는 사람은 비 소식이 있으면 안 함)
//     비/눈 오는 날 : 강수확률 50% 이상, 또는 30% 이상이면서 예상 강수량 3mm 이상
//     추천 good     : 그날 포함 7일 안에 비 소식 없음
//     보통 soso     : 4~7일 뒤 비 소식
//     비추 skip     : 1~3일 뒤 비 소식
//     맑음 clear    : 비 소식은 없지만 예보 기간이 끝나 7일 뒤까지는 알 수 없음
//     얼음 cold     : 최저기온 영하 5도 이하 (셀프세차장 물이 얼 수 있음)
// - 지역은 시·군·구 이름만 휴대폰에 저장 (ppx_ww_region). 정확한 좌표는 보내거나 저장하지 않음
(function () {
  const R = window.WW_REGIONS || [];
  const get = k => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const put = (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} };
  const isRain = (p, mm) => p >= 50 || (mm >= 3 && p >= 30);
  const snowCode = c => (c >= 71 && c <= 77) || c === 85 || c === 86;

  function judge(d, i) {
    const P = d.precipitation_probability_max, M = d.precipitation_sum;
    const p = P[i] ?? 0, n = d.time.length;
    if (isRain(p, M[i] ?? 0)) return snowCode(d.weather_code[i])
      ? { k: 'rain', icon: '❄️', t: '눈', s: '☂ ' + p + '%' }
      : { k: 'rain', icon: '☔', t: '비', s: '☂ ' + p + '%' };
    if (d.temperature_2m_min[i] <= -5) return { k: 'cold', icon: '🥶', t: '얼음', s: '☂ ' + p + '%' };
    let gap = 0;
    for (let k = i + 1; k <= Math.min(i + 7, n - 1); k++) if (isRain(P[k] ?? 0, M[k] ?? 0)) { gap = k - i; break; }
    if (gap && gap <= 3) return { k: 'skip', icon: '🙅', t: '비추', s: '비 ' + gap + '일 뒤', gap };
    if (gap) return { k: 'soso', icon: '⛅', t: '보통', s: '비 ' + gap + '일 뒤', gap };
    if (i + 7 > n - 1) return { k: 'clear', icon: '☀️', t: '맑음', s: '☂ ' + p + '%' };
    return { k: 'good', icon: '✨', t: '추천', s: '☂ ' + p + '%' };
  }

  // 오늘 한 줄 요약 (지도·가이드에서 씀)
  function todayLine(d) {
    const j = judge(d, 0);
    if (j.k === 'good') return { j, text: '오늘 세차 추천 · 7일 동안 비 없음' };
    let next = -1;
    for (let i = 1; i < Math.min(10, d.time.length); i++) if (judge(d, i).k === 'good') { next = i; break; }
    const nx = next > 0 ? ' · 다음 추천 ' + md(d.time[next]) : '';
    if (j.k === 'rain') return { j, text: '오늘은 ' + j.t + ' 소식' + nx };
    if (j.k === 'cold') return { j, text: '오늘은 물이 얼 수 있어요' + nx };
    if (j.k === 'skip' || j.k === 'soso') return { j, text: (j.k === 'skip' ? '오늘은 비추 · ' : '오늘은 보통 · ') + j.gap + '일 뒤 비' + nx };
    return { j, text: '오늘은 맑음' + nx };
  }
  // 아주 짧은 한 줄 (지도 위 작은 띠)
  function shortLine(d) {
    const j = judge(d, 0);
    const t = { good: '오늘 세차 추천', rain: '오늘 ' + j.t + ' 소식', cold: '오늘 물 얼 수 있음', clear: '오늘 맑음',
                skip: '오늘 비추 · ' + j.gap + '일 뒤 비', soso: '오늘 보통 · ' + j.gap + '일 뒤 비' }[j.k];
    return { j, text: t };
  }
  // 미세먼지 하루 등급 (환경부 기준, 낮 07~20시 평균, PM10·PM2.5 중 나쁜 쪽). day 0=오늘 1=내일. 없으면 null
  function dustDay(a, day) {
    if (!a || !a.time) return null;
    const ymd = (a.time[day * 24] || '').slice(0, 10);
    const idx = a.time.map((t, i) => [t, i]).filter(([t]) => { const h = +t.slice(11, 13); return t.slice(0, 10) === ymd && h >= 7 && h <= 20; }).map(x => x[1]);
    const avg = arr => { const v = idx.map(i => arr[i]).filter(x => x != null); return v.length ? v.reduce((s, x) => s + x, 0) / v.length : null; };
    const p10 = avg(a.pm10), p25 = avg(a.pm2_5);
    if (p10 == null || p25 == null) return null;
    const lv = (v, cut) => cut.findIndex(c => v <= c);
    const n = Math.max(lv(p10, [30, 80, 150, Infinity]), lv(p25, [15, 35, 75, Infinity]));
    return { n, label: ['좋음', '보통', '나쁨', '매우 나쁨'][n], p10: Math.round(p10), p25: Math.round(p25) };
  }
  const WD = ['일', '월', '화', '수', '목', '금', '토'];
  function md(t) { const dt = new Date(t + 'T00:00:00+09:00'); return (dt.getMonth() + 1) + '/' + dt.getDate() + '(' + WD[dt.getDay()] + ')'; }

  function nearest(la, lo) {
    let best = R[0], bd = Infinity;
    R.forEach(r => { const d = (r[1] - la) ** 2 + ((r[2] - lo) * Math.cos(la * Math.PI / 180)) ** 2; if (d < bd) { bd = d; best = r; } });
    return best;
  }
  const find = name => R.find(x => x[0] === name) || null;

  async function load(r, withDust) {
    const key = 'ppx_ww3_' + r[0];
    try {
      const c = JSON.parse(get(key) || 'null');
      if (c && Date.now() - c.at < 2 * 3600e3 && (!withDust || c.a)) return c;
    } catch (e) {}
    const ll = `latitude=${r[1]}&longitude=${r[2]}&timezone=Asia%2FSeoul`;
    const [w, a] = await Promise.all([
      fetch(`https://api.open-meteo.com/v1/forecast?${ll}&forecast_days=16`
        + '&daily=weather_code,precipitation_probability_max,precipitation_sum,temperature_2m_min,temperature_2m_max')
        .then(x => x.ok ? x.json() : null).catch(() => null),
      withDust ? fetch(`https://air-quality-api.open-meteo.com/v1/air-quality?${ll}&forecast_days=2&hourly=pm10,pm2_5`)
        .then(x => x.ok ? x.json() : null).catch(() => null) : null
    ]);
    if (!w || !w.daily) return null;
    const out = { at: Date.now(), d: w.daily, a: a && a.hourly ? a.hourly : null };
    put(key, JSON.stringify(out));
    return out;
  }

  window.WW = {
    regions: R, judge, todayLine, shortLine, dustDay, md, nearest, find, load, WD,
    savedRegion: () => find(get('ppx_ww_region') || '') ,
    saveRegion: (name, viaGps) => { put('ppx_ww_region', name); put('ppx_ww_gps', viaGps ? '1' : ''); },
    viaGps: () => get('ppx_ww_gps') === '1'
  };
})();
