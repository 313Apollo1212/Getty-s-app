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
      data: { user },
      error: authError,
    } = await authClient.auth.getUser();

    if (authError || !user) {
      return jsonResponse({ error: 'Unauthorized.' }, 401);
    }

    const body = await req.json();
    const username = String(body.username ?? '').trim().toLowerCase();
    const fullName = String(body.full_name ?? '').trim();
    const newPassword = String(body.new_password ?? '').trim();

    if (!username || !fullName) {
      return jsonResponse({ error: 'Username and full name are required.' }, 400);
    }

    if (newPassword && newPassword.length < 4) {
      return jsonResponse({ error: 'Password must be at least 4 characters.' }, 400);
    }

    const { data: existingUser } = await serviceClient
      .from('profiles')
      .select('id')
      .eq('username', username)
      .neq('id', user.id)
      .maybeSingle();

    if (existingUser) {
      return jsonResponse({ error: 'Username already exists.' }, 409);
    }

    const nextEmail = `${username}@example.com`;

    const { error: authUpdateError } = await serviceClient.auth.admin.updateUserById(user.id, {
      email: nextEmail,
      ...(newPassword ? { password: newPassword } : {}),
      user_metadata: {
        ...user.user_metadata,
        username,
        full_name: fullName,
      },
    });

    if (authUpdateError) {
      return jsonResponse({ error: authUpdateError.message }, 400);
    }

    const { error: profileError } = await serviceClient
      .from('profiles')
      .update({ username, full_name: fullName })
      .eq('id', user.id);

    if (profileError) {
      return jsonResponse({ error: profileError.message }, 400);
    }

    return jsonResponse({ success: true }, 200);
  } catch (error) {
    return jsonResponse({ error: String(error) }, 500);
  }
});
