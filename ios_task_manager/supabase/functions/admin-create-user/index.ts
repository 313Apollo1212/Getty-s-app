import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const authHeader = req.headers.get('Authorization');

    if (!supabaseUrl || !serviceRoleKey || !anonKey || !authHeader) {
      return jsonResponse({ error: 'Missing required environment variables.' }, 500);
    }

    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const serviceClient = createClient(supabaseUrl, serviceRoleKey);

    const {
      data: { user: requester },
      error: authError,
    } = await authClient.auth.getUser();

    if (authError || !requester) {
      return jsonResponse({ error: 'Unauthorized.' }, 401);
    }

    const { data: requesterProfile, error: roleError } = await serviceClient
      .from('profiles')
      .select('role')
      .eq('id', requester.id)
      .single();

    if (roleError || requesterProfile?.role !== 'admin') {
      return jsonResponse({ error: 'Only admins can create users.' }, 403);
    }

    const body = await req.json();
    const username = String(body.username ?? '').trim().toLowerCase();
    const password = String(body.password ?? '');
    const fullName = String(body.full_name ?? '').trim();
    const role = body.role === 'admin' ? 'admin' : 'employee';

    if (!username || !fullName || password.length < 6) {
      return jsonResponse({ error: 'Invalid payload.' }, 400);
    }

    const { data: existing } = await serviceClient
      .from('profiles')
      .select('id')
      .eq('username', username)
      .maybeSingle();

    if (existing != null) {
      return jsonResponse({ error: 'Username already exists.' }, 409);
    }

    const email = `${username}@example.com`;

    const { data: createdUser, error: createError } = await serviceClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        username,
        full_name: fullName,
        role,
      },
    });

    if (createError || !createdUser.user) {
      return jsonResponse({ error: createError?.message ?? 'Unable to create auth user.' }, 400);
    }

    const { error: profileError } = await serviceClient.from('profiles').insert({
      id: createdUser.user.id,
      username,
      full_name: fullName,
      role,
    });

    if (profileError) {
      await serviceClient.auth.admin.deleteUser(createdUser.user.id);
      return jsonResponse({ error: profileError.message }, 400);
    }

    return jsonResponse({ id: createdUser.user.id, username, role }, 201);
  } catch (error) {
    return jsonResponse({ error: String(error) }, 500);
  }
});
