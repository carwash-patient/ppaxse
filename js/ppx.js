// 빡세 공통: Supabase 연결, 로그인, 세차장 데이터
// 사용하는 페이지에서 순서대로 불러옴:
//   1) supabase-js (cdn.jsdelivr.net/npm/@supabase/supabase-js@2)
//   2) js/config.js
//   3) js/ppx.js
(function () {
  const cfg = window.PPX_CONFIG || {};
  const ready = !!(cfg.url && cfg.key && window.supabase && window.supabase.createClient);
  const db = ready ? window.supabase.createClient(cfg.url, cfg.key) : null;

  const PLACE_COLS = 'id,name,addr,region,type,types,lat,lng,tel,hours,price,price_note,h24,foam,under,indoor,myitem,reserve,info,checked_at,check_count,comment_count';

  // 다른 페이지(마이페이지·커뮤니티)가 아직 쓰는 예전 형식의 로그인 정보도 맞춰 둠
  function syncLocalUser(profile, email) {
    try {
      if (!profile) { localStorage.removeItem('ppaxseUser'); return; }
      const prev = JSON.parse(localStorage.getItem('ppaxseUser') || 'null') || {};
      const same = prev.email === email;
      localStorage.setItem('ppaxseUser', JSON.stringify({
        email,
        userNick: profile.nickname || '',
        skill: profile.skill || '',
        cars: profile.cars || [],
        role: profile.role || 'user',
        points: same ? (prev.points || 0) : 0,
        posts: same ? (prev.posts || []) : [],
        lightning: same ? (prev.lightning || []) : []
      }));
    } catch (e) { /* 저장소를 못 쓰는 환경이면 무시 */ }
  }

  function koError(err) {
    const m = (err && (err.message || err.error_description || String(err))) || '';
    if (/Invalid login credentials/i.test(m)) return '이메일 또는 비밀번호가 맞지 않아요';
    if (/Email not confirmed/i.test(m)) return '메일함에서 인증 링크를 먼저 눌러주세요';
    if (/already registered|already been registered/i.test(m)) return '이미 가입된 이메일이에요. 로그인해 주세요';
    if (/Password should be at least/i.test(m)) return '비밀번호가 너무 짧아요';
    if (/rate limit|too many/i.test(m)) return '잠시 후 다시 시도해 주세요';
    if (/Failed to fetch|NetworkError/i.test(m)) return '인터넷 연결을 확인해 주세요';
    if (/Anonymous sign-ins are disabled/i.test(m)) return '지금은 가입 없이 보낼 수 없어요. 로그인해 주세요';
    if (/place_comment_reports_comment_reporter_key/i.test(m)) return '이미 신고하신 한마디예요. 확인 후 조치할게요';
    if (/captcha/i.test(m)) return '사람 확인이 끝나지 않았어요. 다시 시도해 주세요';
    if (/place_checks_once_idx|duplicate key/i.test(m)) return '오늘 이미 확인해 주셨어요. 고마워요!';
    if (/row-level security/i.test(m)) return '보낼 수 없는 내용이에요. 새로고침 후 다시 시도해 주세요';
    return m || '문제가 생겼어요. 잠시 후 다시 시도해 주세요';
  }

  // 예전 방식이 휴대폰에 그대로 저장해 둔 아이디·비밀번호 목록은 지움 (보안)
  try { localStorage.removeItem('ppaxseUsers'); } catch (e) {}

  let profileCache = null;

  // ── 유입 경로 꼬리표 (?ref=cafe 등). 기기에 처음 들어온 경로만 기억 ──
  function myRef() {
    try {
      const q = (new URLSearchParams(location.search).get('ref') || '').toLowerCase();
      if (/^[a-z0-9_-]{1,30}$/.test(q) && !localStorage.getItem('ppxRef')) localStorage.setItem('ppxRef', q);
      return localStorage.getItem('ppxRef') || null;
    } catch (e) { return null; }
  }
  myRef();

  // ── 차종 아이콘 (사진 대신 차종 그림 + 색) ──
  const CAR_PATHS = {
    sedan:  'M6 30 L12 21 Q14 18 18 18 L38 18 Q42 18 45 21 L52 27 L58 28 Q62 29 62 33 L62 38 L4 38 L4 33 Q4 30 6 30 Z',
    coupe:  'M5 31 L15 20 Q17 18 21 18 L34 18 Q39 18 43 22 L50 28 L58 29 Q62 30 62 34 L62 38 L4 38 L4 34 Q4 31 5 31 Z',
    sports: 'M4 33 L16 24 Q19 22 24 22 L36 22 Q41 22 45 25 L52 29 L60 30 Q62 31 62 34 L62 38 L4 38 Z',
    suv:    'M5 28 L10 16 Q11 14 14 14 L42 14 Q45 14 47 17 L53 25 L59 26 Q62 27 62 31 L62 38 L4 38 L4 30 Q4 28 5 28 Z',
    van:    'M4 14 Q4 12 7 12 L44 12 Q48 12 51 16 L58 25 Q62 27 62 31 L62 38 L4 38 Z',
    truck:  'M4 24 L32 24 L32 13 Q32 12 34 12 L46 12 Q49 12 51 15 L56 23 L60 24 Q62 25 62 29 L62 38 L4 38 Z',
    ev:     'M6 30 L12 21 Q14 18 18 18 L38 18 Q42 18 45 21 L52 27 L58 28 Q62 29 62 33 L62 38 L4 38 L4 33 Q4 30 6 30 Z',
    other:  'M6 30 L12 21 Q14 18 18 18 L38 18 Q42 18 45 21 L52 27 L58 28 Q62 29 62 33 L62 38 L4 38 L4 33 Q4 30 6 30 Z'
  };
  function carAvatar(type, color, size) {
    const t = CAR_PATHS[type] ? type : 'sedan';
    const c = /^#[0-9a-f]{6}$/i.test(color || '') ? color : '#22d3ee';
    const s = size || 44;
    // 검정·진회색처럼 어두운 차는 밝은 배경에 그려서 잘 보이게
    const n = parseInt(c.slice(1), 16), lum = (0.299 * (n >> 16) + 0.587 * ((n >> 8) & 255) + 0.114 * (n & 255)) / 255;
    const bg = lum < 0.35 ? '#dbe7f3' : '#0b1d33', hub = lum < 0.35 ? '#94a3b8' : '#cfe8ff';
    const bolt = t === 'ev' ? '<path d="M35 22 L29 31 L33 31 L31 37 L38 28 L34 28 Z" fill="#04111e"/>' : '';
    const boltFill = lum < 0.35 ? '#fbbf24' : '#04111e';
    return `<svg width="${s}" height="${s}" viewBox="0 0 66 66" role="img" aria-label="내 차 아이콘" style="display:block;border-radius:50%;background:${bg}">
      <g transform="translate(0 8)"><path d="${CAR_PATHS[t]}" fill="${c}"/>${bolt.replace('#04111e', boltFill)}
      <circle cx="17" cy="38" r="6" fill="#04111e"/><circle cx="17" cy="38" r="2.5" fill="${hub}"/>
      <circle cx="49" cy="38" r="6" fill="#04111e"/><circle cx="49" cy="38" r="2.5" fill="${hub}"/></g></svg>`;
  }

  // ── 사람 확인(CAPTCHA, Cloudflare Turnstile) ──
  // config.js 에 captcha(사이트 키)를 넣었을 때만 동작. 비어 있으면 아무것도 안 함.
  // 대부분은 화면에 아무것도 안 뜨고, 의심스러울 때만 체크 상자가 뜸.
  let tsLoading = null;
  function loadTurnstile() {
    if (window.turnstile) return Promise.resolve();
    if (!tsLoading) tsLoading = new Promise((ok, no) => {
      const sc = document.createElement('script');
      sc.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
      sc.async = true; sc.onload = () => ok(); sc.onerror = () => { tsLoading = null; no(new Error('captcha load failed')); };
      document.head.appendChild(sc);
    });
    return tsLoading;
  }
  async function captchaToken() {
    if (!cfg.captcha) return undefined;
    await loadTurnstile();
    return new Promise((ok, no) => {
      const box = document.createElement('div');
      box.style.cssText = 'position:fixed;left:50%;bottom:24px;transform:translateX(-50%);z-index:99999';
      document.body.appendChild(box);
      let wid = null;
      const done = (fn, v) => { try { window.turnstile.remove(wid); } catch (e) {} box.remove(); fn(v); };
      wid = window.turnstile.render(box, {
        sitekey: cfg.captcha, appearance: 'interaction-only', language: 'ko',
        callback: t => done(ok, t),
        'error-callback': () => done(no, new Error('captcha failed')),
        'timeout-callback': () => done(no, new Error('captcha timeout'))
      });
    });
  }

  // 제한에 걸린 요청은 운영자가 볼 수 있게 따로 기록 (기록 실패는 무시)
  const LIMIT_RE = /오늘은 더 보낼 수 없어요|초에 한 번씩|같은 내용은|하루 신고는|확인을 기다리는|방금 이 세차장|이 기기에서는 지금 보낼 수 없어요/;
  async function guarded(kind, fn) {
    try { return await fn(); }
    catch (e) {
      const m = (e && (e.message || String(e))) || '';
      if (db && LIMIT_RE.test(m)) { try { await db.rpc('ppx_log_block', { k: kind, m: m.slice(0, 200) }); } catch (x) {} }
      throw e;
    }
  }

  // ── 가입 없이 쓰기 ──
  // 제보·추가 요청·확인을 할 때만 기기에 보이지 않는 이름표(익명 로그인)를 만듦.
  // 가입하거나 로그인하면 그동안 이 기기로 보낸 것을 계정으로 옮김 (1회용 번호 사용)
  const CLAIM_KEY = 'ppxClaim';
  const isAnonUser = u => !!(u && (u.is_anonymous || (u.app_metadata && u.app_metadata.provider === 'anonymous')));
  async function prepareClaim() {
    try {
      const { data: { session } } = await db.auth.getSession();
      if (!session || !isAnonUser(session.user)) return;
      const { data } = await db.rpc('start_claim');
      if (data) localStorage.setItem(CLAIM_KEY, data);
    } catch (e) { /* 옮기기는 덤: 실패해도 가입·로그인은 계속 */ }
  }
  async function finishClaim() {
    let t = null;
    try { t = localStorage.getItem(CLAIM_KEY); } catch (e) {}
    if (!t) return 0;
    try {
      const { data, error } = await db.rpc('finish_claim', { t });
      if (!error) localStorage.removeItem(CLAIM_KEY);
      return data || 0;
    } catch (e) { return 0; }
  }

  // ── 세차장 정보 항목 (지도·제보·후기·운영자 화면이 함께 씀) ──
  // l: 이름, s: 후기 칩 이름, col: places 표의 칸 / 없으면 places.info 안에 저장
  const FIELDS = [
    { k: 'foam',     l: '폼건',          s: '💨 폼건',         col: true },
    { k: 'fbrush',   l: '폼브러시',      s: '🧽 폼브러시' },
    { k: 'wax',      l: '왁스 코팅',     s: '✨ 왁스 코팅' },
    { k: 'steam',    l: '스팀 세차',     s: '🌫️ 스팀세차' },
    { k: 'under',    l: '하부 세차',     s: '⬇️ 하부세차',     col: true },
    { k: 'finisher', l: '마무리 직원',   s: '🙋 마무리 직원' },
    { k: 'gasdisc',  l: '주유 시 할인',  s: '⛽ 주유 시 할인' },
    { k: 'inclean',  l: '실내 청소',     s: '🧼 실내 청소' },
    { k: 'seatout',  l: '시트 탈거',     s: '💺 시트 탈거' },
    { k: 'indoor',   l: '실내 베이',     s: '🏠 실내 베이',    col: true },
    { k: 'hotwater', l: '온수',          s: '♨️ 온수' },
    { k: 'airgun',   l: '에어건',        s: '🌬️ 에어건' },
    { k: 'vacuum',   l: '진공청소기',    s: '🧹 진공청소기' },
    { k: 'mat',      l: '매트 세척기',   s: '🧺 매트 세척기' },
    { k: 'dry',      l: '드라잉 공간',   s: '🧻 드라잉 공간' },
    { k: 'myitem',   l: '개인 용품 사용', s: '🪣 개인 용품 OK', col: true },
    { k: 'reserve',  l: '예약 필요',     s: '📅 예약제',       col: true },
    { k: 'toilet',   l: '화장실',        s: '🚻 화장실' },
    { k: 'h24',      l: '24시간 운영',   s: '🕐 24시간',       col: true },
    { k: 'lounge',   l: '대기 공간',     s: '🛋️ 대기 공간' },
    { k: 'brush',    l: '브러시',        s: '🪥 브러시' }   // 예전 항목: 운영자 화면에만
  ];
  // 세차장 종류별로 받는 항목 (이 순서대로 보여줌)
  const TYPE_FIELDS = {
    self:    ['foam','fbrush','wax','under','indoor','hotwater','airgun','vacuum','mat','dry','myitem','toilet','h24','lounge'],
    notouch: ['under','airgun','vacuum','mat','dry','myitem','toilet','h24','lounge'],
    auto:    ['under','finisher','gasdisc','airgun','vacuum','mat','dry','toilet','h24'],
    hand:    ['steam','under','inclean','reserve','toilet','h24','lounge'],
    detail:  ['steam','under','seatout','reserve','toilet','lounge']
  };
  const TYPE_ORDER = ['self','hand','notouch','auto','detail'];
  // 고른 종류들의 항목을 합침 (겹치면 한 번만). 종류를 모르면 전부
  function fieldsFor(types) {
    let t = TYPE_ORDER.filter(x => (types || []).includes(x));
    if (!t.length) t = TYPE_ORDER;
    const keys = [...new Set(t.flatMap(x => TYPE_FIELDS[x]))];
    return keys.map(k => FIELDS.find(f => f.k === k));
  }
  const PAY = { card: '카드', cash: '현금', coin: '동전 교환기', pay: '간편결제' };
  const SVC = { coat: '코팅', ppf: 'PPF', polish: '광택', interior: '실내 클리닝', tint: '썬팅' };
  const VISIT = { today: '오늘 다녀옴', week: '이번 주', month: '이번 달', older: '더 오래전', none: '직접 안 가봄' };
  // 세차장 종류 → 추가 입력칸 묶음 (self: 칸 수·요금, auto: 높이 제한, hand: 서비스)
  function groupsFor(types) {
    const t = types || [];
    const g = new Set(['all']);
    if (t.includes('self')) g.add('self');
    if (t.includes('notouch') || t.includes('auto')) g.add('auto');
    if (t.includes('hand') || t.includes('detail')) g.add('hand');
    if (g.size === 1) { g.add('self'); g.add('auto'); g.add('hand'); }   // 종류를 모르면 전부
    return g;
  }
  // 항목 값 읽기 (칸 또는 info)
  const fieldVal = (p, f) => f.col ? (p[f.k] ?? null) : ((p.info || {})[f.k] ?? null);

  const PPX = {
    ready,
    db,
    koError,
    captchaToken,
    FIELDS, TYPE_FIELDS, fieldsFor, PAY, SVC, VISIT, groupsFor, fieldVal,

    // 로그인 상태 + 회원 정보(닉네임·역할 등). 로그인 안 했으면 null
    async me() {
      if (!ready) return null;
      const { data: { session } } = await db.auth.getSession();
      if (!session || isAnonUser(session.user)) { profileCache = null; return null; }   // 가입 없이 쓰는 중이면 '로그인 안 함'
      if (profileCache && profileCache.id === session.user.id) return profileCache;
      await finishClaim();
      const { data, error } = await db.from('profiles')
        .select('id,nickname,skill,cars,role,home,avatar_car,avatar_color,car_model').eq('id', session.user.id).maybeSingle();
      if (error) throw error;
      profileCache = data ? { ...data, email: session.user.email } : null;
      syncLocalUser(profileCache, session.user.email);
      return profileCache;
    },

    // 가입 없이 제보할 때: 이미 로그인(또는 익명)이면 그대로, 아니면 익명 이름표를 만듦. 사용자 id 반환
    async ensureUser() {
      const { data: { session } } = await db.auth.getSession();
      if (session) return session.user.id;
      const captchaTk = await captchaToken();
      const ref = myRef();
      const { data, error } = await db.auth.signInAnonymously({ options: { captchaToken: captchaTk, data: ref ? { ref } : {} } });
      if (error) throw error;
      return data.user.id;
    },

    // 지금 기기의 사용자 id (가입 없이 쓰는 중이어도). 아무것도 없으면 null
    async myId() {
      if (!ready) return null;
      const { data: { session } } = await db.auth.getSession();
      return session ? session.user.id : null;
    },

    async isAnon() {
      if (!ready) return false;
      const { data: { session } } = await db.auth.getSession();
      return !!session && isAnonUser(session.user);
    },

    async signIn(email, password) {
      await prepareClaim();
      const captchaTk = await captchaToken();
      const { error } = await db.auth.signInWithPassword({ email, password, options: captchaTk ? { captchaToken: captchaTk } : undefined });
      if (error) throw error;
      profileCache = null;
      return PPX.me();
    },

    // 반환값: 바로 로그인되면 회원 정보, 메일 인증이 필요하면 { needsConfirm: true }
    async signUp({ email, password, nickname, skill, cars, avatar_car, avatar_color, car_model, signup_source, signup_note, age14 }) {
      // 인증 메일 링크를 누르면 로그인 화면 → 원래 보던 곳(?next=)으로
      const nx = new URLSearchParams(location.search).get('next');
      const back = location.href.replace(/[^/]*$/, '') + 'login.html' +
        (nx && /^(r\/(\?[\w=&%-]*)?|[\w-]+\.html(\?[\w=&%-]*)?)$/.test(nx) ? '?next=' + encodeURIComponent(nx) : '');
      await prepareClaim();
      const captchaTk = await captchaToken();
      const { data, error } = await db.auth.signUp({
        email, password,
        options: { data: { nickname, skill, cars, avatar_car, avatar_color, car_model, signup_source, signup_note, age14: !!age14, ref: myRef() }, emailRedirectTo: back, captchaToken: captchaTk }
      });
      if (error) throw error;
      // 이미 가입된 이메일이면 Supabase가 빈 identities 로 응답함
      if (data.user && Array.isArray(data.user.identities) && data.user.identities.length === 0) {
        throw new Error('already registered');
      }
      if (!data.session) return { needsConfirm: true };
      profileCache = null;
      return PPX.me();
    },

    async signOut() {
      if (ready) await db.auth.signOut();
      profileCache = null;
      syncLocalUser(null);
    },

    carAvatar,
    myRef,
    // 내 차 아이콘·모델 바꾸기
    async updateAvatar({ avatar_car, avatar_color, car_model }) {
      const me = await PPX.me();
      if (!me) throw new Error('로그인이 필요해요');
      const { error } = await db.from('profiles')
        .update({ avatar_car: avatar_car || null, avatar_color: avatar_color || null, car_model: (car_model || '').trim().slice(0, 40) || null })
        .eq('id', me.id);
      if (error) throw error;
      profileCache = null;
    },
    // 회원 탈퇴: 계정·프로필 즉시 삭제
    async deleteAccount() {
      const { error } = await db.rpc('delete_my_account');
      if (error) throw error;
      try { await db.auth.signOut(); } catch (e) {}
      profileCache = null;
      syncLocalUser(null);
      try { ['ppxNick', 'ppaxseUser'].forEach(k => localStorage.removeItem(k)); } catch (e) {}
    },
    // 운영자: 채널별 새 방문자 → 응모 → 가입
    async adminChannelStats(days) {
      const { data, error } = await db.rpc('admin_channel_stats', { days: days || 30 });
      if (error) throw error;
      return data;
    },

    // 승인된 세차장 전부. 개수를 먼저 알아낸 뒤 1,000개씩 동시에 4묶음씩 받아 빠르게 불러옴
    async approvedPlaces() {
      const step = 1000;
      const head = await db.from('places').select('id', { count: 'exact', head: true }).eq('status', 'approved');
      if (head.error) throw head.error;
      const total = head.count || 0, pages = Math.ceil(total / step), out = new Array(pages);
      for (let i = 0; i < pages; i += 4) {
        await Promise.all(Array.from({ length: Math.min(4, pages - i) }, async (_, k) => {
          const from = (i + k) * step;
          const { data, error } = await db.from('places').select(PLACE_COLS)
            .eq('status', 'approved').order('id').range(from, from + step - 1);
          if (error) throw error;
          out[i + k] = data;
        }));
      }
      // 받는 사이에 새로 승인된 곳이 있어 마지막 묶음이 꽉 찼으면 남은 것도 받음
      for (let from = pages * step; ; from += step) {
        if (pages && out[pages - 1].length < step) break;
        const { data, error } = await db.from('places').select(PLACE_COLS)
          .eq('status', 'approved').order('id').range(from, from + step - 1);
        if (error) throw error;
        out.push(data);
        if (data.length < step) break;
      }
      const seen = new Set();
      return out.flat().filter(p => !seen.has(p.id) && seen.add(p.id));
    },

    // ── 기본 지역 (지도를 열 때 위치를 못 받으면 여기로) ──
    // 이 기기에 저장 + 로그인했으면 계정에도 저장해서 다른 기기에서도 쓰임
    async getHome() {
      let me = null;
      try { me = await PPX.me(); } catch (e) {}
      if (me && me.home && me.home.region) return me.home.region;
      try { const h = JSON.parse(localStorage.getItem('ppxHome') || 'null'); return h && h.region || null; } catch (e) { return null; }
    },
    async setHome(region) {
      try {
        if (region) localStorage.setItem('ppxHome', JSON.stringify({ region }));
        else localStorage.removeItem('ppxHome');
      } catch (e) {}
      let me = null;
      try { me = await PPX.me(); } catch (e) {}
      if (!me) return;
      const home = region ? { region } : null;
      const { error } = await db.from('profiles').update({ home }).eq('id', me.id);
      if (!error && profileCache) profileCache.home = home;
    },

    // 세차장 추가 요청 → '대기' 상태로 저장 (서버에서 강제)
    async requestPlace(p) { return guarded('place', async () => {
      await PPX.ensureUser();
      const { data, error } = await db.from('places').insert({
        name: p.name, addr: p.addr || '', region: p.region || '', type: p.type,
        types: p.types && p.types.length ? p.types : [p.type],
        lat: p.lat, lng: p.lng, tel: p.tel || null, memo: p.memo || null
      }).select('id,name,status').single();
      if (error) throw error;
      return data;
    }); },

    async myRequests() {
      const uid = await PPX.myId();
      if (!uid) return [];
      const { data, error } = await db.from('places')
        .select('id,name,addr,status,reject_reason,created_at')
        .eq('submitted_by', uid).neq('source', 'public_data')
        .order('created_at', { ascending: false }).limit(30);
      if (error) throw error;
      return data;
    },

    // ── 운영자 전용 (서버 권한 규칙으로도 막혀 있음) ──
    async adminList(status) {
      let q = db.from('places')
        .select('id,name,addr,region,type,types,lat,lng,tel,memo,status,reject_reason,created_at,reviewed_at,submitted_by,submitter:profiles!places_submitted_by_fkey(nickname,blocked)');
      q = status === 'pending'
        ? q.eq('status', 'pending').order('created_at', { ascending: true })
        : q.in('status', ['approved', 'rejected']).eq('source', 'user').order('reviewed_at', { ascending: false }).limit(50);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },

    async adminReview(id, status, fields) {
      const patch = { ...(fields || {}), status };
      const { data, error } = await db.from('places').update(patch).eq('id', id).select('id,status').single();
      if (error) throw error;
      return data;
    },

    // 등록된 세차장 정보 고치기 (종류·시설·숨김 등)
    async adminUpdate(id, fields) {
      const { data, error } = await db.from('places').update(fields).eq('id', id)
        .select(PLACE_COLS + ',status').single();
      if (error) throw error;
      return data;
    },

    // 지도에 있거나 숨긴 세차장을 이름·주소·지역으로 검색
    async adminSearch(q) {
      const term = String(q || '').replace(/[,()%*\\]/g, ' ').trim();
      if (!term) return [];
      const { data, error } = await db.from('places').select(PLACE_COLS + ',status')
        .in('status', ['approved', 'closed', 'unlocated'])
        .or(`name.ilike.%${term}%,addr.ilike.%${term}%,region.ilike.%${term}%`)
        .order('name').limit(30);
      if (error) throw error;
      return data;
    },

    // ── 정보 제보 ("정보가 달라요") ──
    // suggest 예: { type:'notouch', foam:true, under:null, closed:true }  (바꾸자는 항목만)
    // extra: { visit: 'today'|'week'|'month'|'older'|'none', photo: 가격표 사진(Blob) }
    async reportPlace(placeId, suggest, memo, extra) { return guarded('report', async () => {
      const uid = await PPX.ensureUser();
      const ex = extra || {};
      let photo = null;
      if (ex.photo) {
        // 사진을 올리기 전에 보낼 수 있는 제보인지 먼저 확인 (못 보낼 제보의 사진이 남지 않게)
        const pre = await db.rpc('ppx_precheck', { what: 'report', pid: placeId });
        if (pre.error) throw pre.error;
        photo = `${uid}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`;
        const up = await db.storage.from('report-photos').upload(photo, ex.photo, { contentType: 'image/jpeg', upsert: false });
        if (up.error) throw up.error;
      }
      const { data, error } = await db.from('place_reports')
        .insert({ place_id: placeId, suggest: suggest || {}, memo: memo || null, visit: ex.visit || null, photo, via: ex.via || 'map' })
        .select('id,status').single();
      if (error) throw error;
      return data;
    }); },

    // ── 후기 페이지 (r/) ──
    // 이름·주소·지역 검색. 띄어쓰기로 나눈 낱말이 모두 들어간 곳 (예: "구월 셀프")
    async searchPlaces(text, limit) {
      const words = String(text || '').replace(/[,()%*\\.]/g, ' ').split(/\s+/).filter(Boolean).slice(0, 4);
      if (!words.length) return [];
      let q = db.from('places').select(PLACE_COLS).eq('status', 'approved');
      words.forEach(w => { q = q.or(`name.ilike.%${w}%,addr.ilike.%${w}%,region.ilike.%${w}%`); });
      const { data, error } = await q.order('name').limit(limit || 30);
      if (error) throw error;
      return data;
    },

    // 내 주변: 위치 둘레 네모 안에서 찾기 (가까운 순 정렬은 화면에서)
    async nearPlaces(lat, lng, km) {
      const d = (km || 3) / 111, dl = d / Math.cos(lat * Math.PI / 180);
      const { data, error } = await db.from('places').select(PLACE_COLS).eq('status', 'approved')
        .gte('lat', lat - d).lte('lat', lat + d).gte('lng', lng - dl).lte('lng', lng + dl).limit(300);
      if (error) throw error;
      return data;
    },

    async placeById(id) {
      const { data, error } = await db.from('places').select(PLACE_COLS).eq('id', id).eq('status', 'approved').maybeSingle();
      if (error) throw error;
      return data;
    },

    // 한마디
    async comments(placeId, limit) {
      const { data, error } = await db.from('place_comments').select('id,nickname,body,created_at')
        .eq('place_id', placeId).eq('hidden', false).order('created_at', { ascending: false }).limit(limit || 20);
      if (error) throw error;
      return data;
    },
    async addComment(placeId, body, nickname) { return guarded('comment', async () => {
      await PPX.ensureUser();
      const { data, error } = await db.from('place_comments')
        .insert({ place_id: placeId, body: String(body).trim().slice(0, 200), nickname: nickname ? String(nickname).trim().slice(0, 20) : null })
        .select('id,nickname,body,created_at').single();
      if (error) throw error;
      return data;
    }); },

    // ── 한마디 기프티콘 주간 추첨 ──
    // 한마디를 저장한 직후 응모 (조건 검사는 DB가 함). 돌려주는 값: { code, week, already }
    async enterEvent(commentId) {
      const { data, error } = await db.rpc('ppx_enter_event', { cid: commentId });
      if (error) throw error;
      return data;
    },
    // 이번 주 참여 수(실제 숫자), 지난 회차 당첨 번호, 내 응모번호 (누구나)
    async eventStatus() {
      const { data, error } = await db.rpc('ppx_event_status');
      if (error) throw error;
      return data;
    },
    async adminEventWeek(week) {
      const { data, error } = await db.rpc('admin_event_week', { w: week });
      if (error) throw error;
      return data || [];
    },
    async adminEventDraw(week, redraw) {
      const { data, error } = await db.rpc('admin_event_draw', { w: week, redraw: !!redraw });
      if (error) throw error;
      return data || [];
    },

    // 모인 정보 수 (누구나)
    async stats() {
      const { data, error } = await db.rpc('ppx_stats');
      if (error) throw error;
      return data;
    },

    // 운영자: 이벤트(기프티콘 추첨) 응모자 — 기간 안에 후기를 남긴 가입 회원
    async adminEventEntries(from, to) {
      const { data, error } = await db.rpc('admin_event_entries', { p_from: from, p_to: to });
      if (error) throw error;
      return data;
    },

    // 한마디 신고 (한 익명 로그인 세션/계정당 한마디 1회, 하루 10회 제한은 DB에서 검사)
    async reportComment(commentId, reason) { return guarded('comment_report', async () => {
      await PPX.ensureUser();
      const { error } = await db.from('place_comment_reports').insert({ comment_id: commentId, reason });
      if (error) throw error;
    }); },

    // 운영자: 접수된 한마디 신고
    async adminCommentReports(status) {
      let q = db.from('place_comment_reports')
        .select('id,comment_id,reason,status,created_at,comment:place_comments!place_comment_reports_comment_id_fkey(id,place_id,body,nickname,hidden,created_at,place:places!place_comments_place_id_fkey(name,region,lat,lng))');
      q = status === 'pending' ? q.eq('status', 'pending').order('created_at', { ascending: true })
        : q.eq('status', 'resolved').order('created_at', { ascending: false }).limit(60);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },
    async adminResolveCommentReport(id) {
      const { error } = await db.from('place_comment_reports').update({ status: 'resolved' }).eq('id', id);
      if (error) throw error;
    },
    // 운영자: 한 한마디에 쌓인 신고를 한꺼번에 처리
    async adminResolveCommentReports(commentId) {
      const { error } = await db.from('place_comment_reports').update({ status: 'resolved' })
        .eq('comment_id', commentId).eq('status', 'pending');
      if (error) throw error;
    },
    // 운영자: 최근 7일 이상 요청 (사람별로 묶음, 많은 순)
    // 운영자: 방문자 통계 (최근 days일)
    async adminVisitStats(days) {
      const { data, error } = await db.rpc('admin_visit_stats', { days: days || 14 });
      if (error) throw error;
      return data;
    },
    // 이 기기를 방문자 수에서 빼기 (운영자 기기)
    noTrack() { try { localStorage.setItem('ppxNoTrack', '1'); } catch (e) {} },

    async adminAbuseSummary() {
      const { data, error } = await db.rpc('admin_abuse_summary');
      if (error) throw error;
      return data || [];
    },

    // 운영자: 한마디 관리
    async adminComments() {
      const { data, error } = await db.from('place_comments')
        .select('id,place_id,nickname,body,hidden,created_at,place:places!place_comments_place_id_fkey(name,region)')
        .order('created_at', { ascending: false }).limit(60);
      if (error) throw error;
      return data;
    },
    async adminHideComment(id, hide) {
      const { error } = await db.from('place_comments').update({ hidden: !!hide }).eq('id', id);
      if (error) throw error;
    },
    async adminBlockCommenter(id) {
      const { error } = await db.rpc('admin_block_commenter', { cid: id });
      if (error) throw error;
    },

    // 내가 보낸 제보 (가입 없이 보낸 것 포함)
    async myReports() {
      const uid = await PPX.myId();
      if (!uid) return [];
      const { data, error } = await db.from('place_reports')
        .select('id,suggest,memo,status,created_at,place:places!place_reports_place_id_fkey(name)')
        .eq('reporter', uid).order('created_at', { ascending: false }).limit(30);
      if (error) throw error;
      return data;
    },

    // '정보가 맞아요' (한 세차장에 하루 한 번)
    async checkPlace(placeId) { return guarded('check', async () => {
      await PPX.ensureUser();
      const { error } = await db.from('place_checks').insert({ place_id: placeId });
      if (error) throw error;
      return true;
    }); },

    // 방문자가 고른 대표 종류(1개) + 같이 있는 종류 → 1인 1표 (30일 안에 다시 고르면 고친 것으로)
    async voteType(placeId, main, extras) {
      await PPX.ensureUser();
      const { error } = await db.rpc('ppx_vote_type', { pid: placeId, m: main, ex: extras || [] });
      if (error) throw error;
      return true;
    },
    // 운영자: 세차장별 대표 종류 표 수 { "336": { auto: 3, self: 1 } }
    async adminTypeVotes() {
      const { data, error } = await db.rpc('admin_type_votes');
      if (error) throw error;
      return data || {};
    },

    // 운영자: 가격표 사진 보기 (10분짜리 임시 주소)
    async adminPhotoUrl(path) {
      const { data, error } = await db.storage.from('report-photos').createSignedUrl(path, 600);
      if (error) throw error;
      return data.signedUrl;
    },

    // 운영자: 장난 제보를 반복하는 사람(기기) 막기/풀기
    async adminBlock(uid, on) {
      const { error } = await db.rpc('admin_block', { uid, on_off: !!on });
      if (error) throw error;
    },

    async adminReports(status) {
      let q = db.from('place_reports')
        .select('id,place_id,suggest,memo,visit,photo,via,reporter,status,created_at,reviewed_at,' +
                'place:places!place_reports_place_id_fkey(' + PLACE_COLS + ',status),' +
                'reporter_p:profiles!place_reports_reporter_fkey(nickname,blocked)');
      q = status === 'pending'
        ? q.eq('status', 'pending').order('created_at', { ascending: true })
        : q.in('status', ['applied', 'dismissed']).order('reviewed_at', { ascending: false }).limit(50);
      const { data, error } = await q;
      if (error) throw error;
      return data;
    },

    async adminResolveReport(id, status) {
      const { data, error } = await db.from('place_reports').update({ status }).eq('id', id)
        .select('id,status').single();
      if (error) throw error;
      return data;
    }
  };

  window.PPX = PPX;

  // ── 방문자 수 세기 ──
  // 기기마다 임의 번호 하나(개인을 알 수 있는 정보 아님)로 '오늘 이 화면을 봤다'만 남김.
  // 운영자 기기, 자동 프로그램은 세지 않음. 실패해도 화면에는 영향 없음.
  try {
    const path = location.pathname;
    const name = /\/r\/(index\.html)?$/.test(path) ? 'review'
      : ((path.match(/([\w-]+)\.html$/) || [, 'index'])[1]);
    const PAGE = { index: 'home', map: 'map', review: 'review', login: 'login', join: 'join', mypage: 'mypage' };
    if (ready && name !== 'admin' && !navigator.webdriver && !localStorage.getItem('ppxNoTrack')) {
      let v = localStorage.getItem('ppxVisitor');
      if (!v || !/^[0-9a-f-]{36}$/.test(v)) {
        v = (crypto.randomUUID ? crypto.randomUUID()
          : '10000000-1000-4000-8000-100000000000'.replace(/[018]/g, c =>
              (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16)));
        localStorage.setItem('ppxVisitor', v);
      }
      setTimeout(() => { db.rpc('ppx_track', { v, p: PAGE[name] || 'other', r: myRef() }).then(() => {}, () => {}); }, 1200);
    }
  } catch (e) { /* 저장소를 못 쓰는 환경이면 세지 않음 */ }
})();
