// 빡세 공통: Supabase 연결, 로그인, 세차장 데이터
// 사용하는 페이지에서 순서대로 불러옴:
//   1) supabase-js (cdn.jsdelivr.net/npm/@supabase/supabase-js@2)
//   2) js/config.js
//   3) js/ppx.js
(function () {
  const cfg = window.PPX_CONFIG || {};
  const ready = !!(cfg.url && cfg.key && window.supabase && window.supabase.createClient);
  const db = ready ? window.supabase.createClient(cfg.url, cfg.key) : null;

  const PLACE_COLS = 'id,name,addr,region,type,lat,lng,tel,hours,price,h24,foam,under,indoor,myitem,reserve';

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
    return m || '문제가 생겼어요. 잠시 후 다시 시도해 주세요';
  }

  // 예전 방식이 휴대폰에 그대로 저장해 둔 아이디·비밀번호 목록은 지움 (보안)
  try { localStorage.removeItem('ppaxseUsers'); } catch (e) {}

  let profileCache = null;

  const PPX = {
    ready,
    db,
    koError,

    // 로그인 상태 + 회원 정보(닉네임·역할 등). 로그인 안 했으면 null
    async me() {
      if (!ready) return null;
      const { data: { session } } = await db.auth.getSession();
      if (!session) { profileCache = null; return null; }
      if (profileCache && profileCache.id === session.user.id) return profileCache;
      const { data, error } = await db.from('profiles')
        .select('id,nickname,skill,cars,role').eq('id', session.user.id).maybeSingle();
      if (error) throw error;
      profileCache = data ? { ...data, email: session.user.email } : null;
      syncLocalUser(profileCache, session.user.email);
      return profileCache;
    },

    async signIn(email, password) {
      const { error } = await db.auth.signInWithPassword({ email, password });
      if (error) throw error;
      profileCache = null;
      return PPX.me();
    },

    // 반환값: 바로 로그인되면 회원 정보, 메일 인증이 필요하면 { needsConfirm: true }
    async signUp({ email, password, nickname, skill, cars }) {
      const back = location.href.replace(/[^/]*$/, '') + 'login.html';
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

    // 승인된 세차장 전부 (한 번에 1,000개씩 나눠 받음)
    async approvedPlaces() {
      const all = [], step = 1000;
      for (let from = 0; ; from += step) {
        const { data, error } = await db.from('places').select(PLACE_COLS)
          .eq('status', 'approved').order('id').range(from, from + step - 1);
        if (error) throw error;
        all.push(...data);
        if (data.length < step) break;
      }
      return all;
    },

    // 세차장 추가 요청 → '대기' 상태로 저장 (서버에서 강제)
    async requestPlace(p) {
      const { data, error } = await db.from('places').insert({
        name: p.name, addr: p.addr || '', region: p.region || '', type: p.type,
        lat: p.lat, lng: p.lng, tel: p.tel || null, memo: p.memo || null
      }).select('id,name,status').single();
      if (error) throw error;
      return data;
    },

    async myRequests() {
      const me = await PPX.me();
      if (!me) return [];
      const { data, error } = await db.from('places')
        .select('id,name,addr,status,reject_reason,created_at')
        .eq('submitted_by', me.id).neq('source', 'public_data')
        .order('created_at', { ascending: false }).limit(30);
      if (error) throw error;
      return data;
    },

    // ── 운영자 전용 (서버 권한 규칙으로도 막혀 있음) ──
    async adminList(status) {
      let q = db.from('places')
        .select('id,name,addr,region,type,lat,lng,tel,memo,status,reject_reason,created_at,reviewed_at,submitter:profiles!places_submitted_by_fkey(nickname)');
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
    }
  };

  window.PPX = PPX;
})();
