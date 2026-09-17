import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/models.dart';
import '../../core/theme.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _supabase = Supabase.instance.client;
  List<FriendRequest> _requests = [];
  List<FriendUser> _friends = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      _supabase.rpc('list_friend_requests'),
      _supabase.rpc('list_friends'),
    ]);
    if (!mounted) return;
    setState(() {
      _requests = (results[0] as List).map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList();
      _friends = (results[1] as List).map((e) => FriendUser.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _respond(String userId, bool accept) async {
    await _supabase.rpc('respond_friend_request', params: {'p_user_id': userId, 'p_accept': accept});
    _load();
  }

  Future<void> _addFriend() async {
    final inputCtrl = TextEditingController();
    String? error;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Agregar amigo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: inputCtrl,
                decoration: const InputDecoration(labelText: 'Correo o usuario de tu amigo'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                var input = inputCtrl.text.trim();
                if (input.isEmpty) return;
                final isEmail = input.contains('@');
                // La app muestra el usuario de otros siempre como "@usuario"
                // (ver Profile.displayName), asi que es natural que alguien
                // escriba el "@" aca tambien al buscar por usuario -- se le
                // saca antes de comparar, si no nunca va a coincidir.
                if (!isEmail && input.startsWith('@')) {
                  input = input.substring(1);
                }
                setState(() => error = null);
                try {
                  final rpcName = isEmail ? 'find_user_by_email' : 'find_user_by_username';
                  final paramName = isEmail ? 'p_email' : 'p_usuario';
                  final found = await _supabase.rpc(rpcName, params: {paramName: input});
                  final list = found as List;
                  if (list.isEmpty) {
                    setState(() => error = 'No se encontro ningun usuario con ese dato.');
                    return;
                  }
                  await _supabase.rpc('send_friend_request', params: {'p_friend_id': list.first['id']});
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  _load();
                } catch (e) {
                  // Antes, si esta busqueda fallaba (ej. la funcion RPC no
                  // existia todavia por una migracion pendiente, o un error
                  // de red), no se mostraba nada -- parecia que el usuario
                  // "no existia" cuando en realidad la busqueda ni se pudo
                  // completar. Ahora se muestra el error real.
                  setState(() => error = e.toString());
                }
              },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos'),
        actions: [IconButton(icon: const Icon(Icons.person_add), onPressed: _addFriend)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_requests.isNotEmpty) ...[
                    const Text('Solicitudes pendientes', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._requests.map((r) => Card(
                          child: ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(r.displayName),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check, color: AppColors.verde),
                                  onPressed: () => _respond(r.userId, true),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.redAccent),
                                  onPressed: () => _respond(r.userId, false),
                                ),
                              ],
                            ),
                          ),
                        )),
                    const SizedBox(height: 20),
                  ],
                  const Text('Mis amigos', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_friends.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Todavia no tienes amigos agregados. Usa el boton + para invitar a alguien por correo.',
                        style: TextStyle(color: AppColors.grisUI),
                      ),
                    ),
                  ..._friends.map((f) => Card(
                        child: ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(f.displayName),
                        ),
                      )),
                ],
              ),
            ),
    );
  }
}
