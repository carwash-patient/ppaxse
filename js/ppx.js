// 빡세 공통: Supabase 연결, 로그인, 세차장 데이터
// 사용하는 페이지에서 순서대로 불러옴:
//   1) supabase-js (cdn.jsdelivr.net/npm/@supabase/supabase-js@2)
//   2) js/config.js
//   3) js/ppx.js
(function () {
  const cfg = window.PPX_CONFIG || {};
  const ready = !!(cfg.url && cfg.key && window.supabase && window.supabase.createClient);
  const db = ready ? window.supabase.createClient(cfg.url, cfg.key) : null;

  const PLACE_COLS = 'id,name,addr,region,type,types,lat,lng,tel,hours,price,h24,foam,under,indoor,myitem,reserve,info,checked_at,check_count';

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
    if (/place_checks_once_idx|duplicate key/i.test(m)) return '오늘 이미 확인해 주셨어요. 고마워요!';
    if (/row-level security/i.test(m)) return '보낼 수 없는 내용이에요. 새로고침 후 다시 시도해 주세요';
    return m || '문제가 생겼어요. 잠시 후 다시 시도해 주세요';
  }

  // 예전 방식이 휴대폰에 그대로 저장해 둔 아이디·비밀번호 목록은 지움 (보안)
  try { localStorage.removeItem('ppaxseUsers'); } catch (e) {}

  let profileCache = null;

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

  // ── 세차장 정보 항목 (지도·제보·운영자 화면이 함께 씀) ──
  // g: 어떤 종류에 보여줄지 (all=모든 세차장, self=셀프, auto=노터치·자동, hand=손세차·디테일링)
  // col: places 표의 칸 / 없으면 places.info 안에 저장
  const FIELDS = [
    { k: 'h24',      l: '24시간 운영',   g: 'all',  col: true },
    { k: 'toilet',   l: '화장실',        g: 'all' },
    { k: 'lounge',   l: '대기 공간',     g: 'all' },
    { k: 'foam',     l: '폼건 사용',     g: 'self', col: true },
    { k: 'under',    l: '하부 세차',     g: 'self', col: true },
    { k: 'indoor',   l: '실내 베이',     g: 'self', col: true },
    { k: 'hotwater', l: '온수',          g: 'self' },
    { k: 'myitem',   l: '개인 용품 사용', g: 'self', col: true },
    { k: 'vacuum',   l: '진공청소기',    g: 'self' },
    { k: 'airgun',   l: '에어건',        g: 'self' },
    { k: 'mat',      l: '매트 세척기',   g: 'self' },
    { k: 'dry',      l: '드라잉 공간',   g: 'self' },
    { k: 'brush',    l: '브러시',        g: 'auto' },
    { k: 'reserve',  l: '예약 필요',     g: 'hand', col: true }
  ];
  const PAY = { card: '카드', cash: '현금', coin: '동전 교환기', pay: '간편결제' };
  const SVC = { coat: '코팅', ppf: 'PPF', polish: '광택', interior: '실내 클리닝', tint: '썬팅' };
  const VISIT = { today: '오늘 다녀옴', week: '이번 주', month: '이번 달', older: '더 오래전', none: '직접 안 가봄' };
  // 세차장 종류 → 보여줄 항목 묶음
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
    FIELDS, PAY, SVC, VISIT, groupsFor, fieldVal,

    // 로그인 상태 + 회원 정보(닉네임·역할 등). 로그인 안 했으면 null
    async me() {
      if (!ready) return null;
      const { data: { session } } = await db.auth.getSession();
      if (!session || isAnonUser(session.user)) { profileCache = null; return null; }   // 가입 없이 쓰는 중이면 '로그인 안 함'
      if (profileCache && profileCache.id === session.user.id) return profileCache;
      await finishClaim();
      const { data, error } = await db.from('profiles')
        .select('id,nickname,skill,cars,role,home').eq('id', session.user.id).maybeSingle();
      if (error) throw error;
      profileCache = data ? { ...data, email: session.user.email } : null;
      syncLocalUser(profileCache, session.user.email);
      return profileCache;
    },

    // 가입 없이 제보할 때: 이미 로그인(또는 익명)이면 그대로, 아니면 익명 이름표를 만듦. 사용자 id 반환
    async ensureUser() {
      const { data: { session } } = await db.auth.getSession();
      if (session) return session.user.id;
      const { data, error } = await db.auth.signInAnonymously();
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
      const { error } = await db.auth.signInWithPassword({ email, password });
      if (error) throw error;
      profileCache = null;
      return PPX.me();
    },

    // 반환값: 바로 로그인되면 회원 정보, 메일 인증이 필요하면 { needsConfirm: true }
    async signUp({ email, password, nickname, skill, cars }) {
      const back = location.href.replace(/[^/]*$/, '') + 'login.html';
      await prepareClaim();
      const { data, error } = await db.auth.signUp({
        email, password,
        options: { data: { nickname, skill, cars }, emailRedirectTo: back }
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
    async requestPlace(p) {
      await PPX.ensureUser();
      const { data, error } = await db.from('places').insert({
        name: p.name, addr: p.addr || '', region: p.region || '', type: p.type,
        types: p.types && p.types.length ? p.types : [p.type],
        lat: p.lat, lng: p.lng, tel: p.tel || null, memo: p.memo || null
      }).select('id,name,status').single();
      if (error) throw error;
      return data;
    },

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
    async reportPlace(placeId, suggest, memo, extra) {
      const uid = await PPX.ensureUser();
      const ex = extra || {};
      let photo = null;
      if (ex.photo) {
        photo = `${uid}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`;
        const up = await db.storage.from('report-photos').upload(photo, ex.photo, { contentType: 'image/jpeg', upsert: false });
        if (up.error) throw up.error;
      }
      const { data, error } = await db.from('place_reports')
        .insert({ place_id: placeId, suggest: suggest || {}, memo: memo || null, visit: ex.visit || null, photo })
        .select('id,status').single();
      if (error) throw error;
      return data;
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
    async checkPlace(placeId) {
      await PPX.ensureUser();
      const { error } = await db.from('place_checks').insert({ place_id: placeId });
      if (error) throw error;
      return true;
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
        .select('id,place_id,suggest,memo,visit,photo,reporter,status,created_at,reviewed_at,' +
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
})();
