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
      return jsonResponse({ error: 'Only admins can reset passwords.' }, 403);
    }

    const body = await req.json();
    const userId = String(body.user_id ?? '').trim();
    const newPassword = String(body.new_password ?? '');

    if (!userId || newPassword.length < 6) {
      return jsonResponse({ error: 'Invalid payload.' }, 400);
    }

    const { error: updateError } = await serviceClient.auth.admin.updateUserById(userId, {
      password: newPassword,
    });

    if (updateError) {
      return jsonResponse({ error: updateError.message }, 400);
    }

    return jsonResponse({ success: true }, 200);
  } catch (error) {
    return jsonResponse({ error: String(error) }, 500);
  }
});
