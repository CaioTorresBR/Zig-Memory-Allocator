const std = @import("std");

const Header = struct {
    len: usize,
    free: bool,
};

const header_alignment = std.mem.Alignment.of(Header);

const AllocateurEtiquette = struct {
    buffer: []u8,
    next: usize,

    /// Crée un allocateur à étiquetage gérant la zone de mémoire délimitée
    /// par la tranche `buffer`.
    fn init(buffer: []u8) AllocateurEtiquette {
        return .{
            .buffer = buffer,
            .next = 0,
        };
    }

    /// Retourne l’interface générique d’allocateur correspondant à
    /// cet allocateur à étiquetage.
    fn allocator(self: *AllocateurEtiquette) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .free = free,
                .resize = std.mem.Allocator.noResize,
                .remap = std.mem.Allocator.noRemap,
            },
        };
    }

    /// Tente d’allouer un bloc de mémoire de `len` octets dont l’adresse
    /// est alignée suivant `alignment`. Retourne un pointeur vers le début
    /// du bloc alloué, ou `null` pour indiquer un échec d’allocation.
    fn alloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        // le paramètre `return_address` peut être ignoré dans ce contexte
        _ = return_address;

        // récupère un pointeur vers l’instance de notre allocateur
        const self: *AllocateurEtiquette = @ptrCast(@alignCast(ctx));

        const header_size = @sizeOf(Header);
        const buff_len = self.buffer.len;

        // par la suite, `self.buffer` et `self.next` désignent les deux
        // champs de l’allocateur
        // Le plus grand alignement entre header et données
        const user_align = alignment.toByteUnits();
        const header_align = header_alignment.toByteUnits();
        const required_align: usize =
            if (user_align > header_align) user_align else header_align;

        // On calcule où les données doivent commencer
        const aligned_data_index = std.mem.alignForward(usize, self.next + header_size, required_align);
       
       
       // L'adresse exacte du header
        const header_index = aligned_data_index - header_size;
        
        // L'adresse de début des données allouées.
        const data_index = aligned_data_index;

        // Vérifier si la taille est suffit dans le buffer
        if (data_index + len > buff_len)
            return null;

        // Header
        const header_bytes_ptr: [*]u8 = self.buffer.ptr + header_index;
        const header_ptr: *Header = @ptrCast(@alignCast(header_bytes_ptr));

        header_ptr.* = Header{ .len = len, .free = false };

        // Mise a jour le prochaine index libre
        self.next = data_index + len;

        // Retourne le ptr au débur des données
        return self.buffer.ptr + data_index;
    }

    /// Récupère l’en-tête associé à l’allocation débutant à l’adresse `ptr`.
    fn getHeader(ptr: [*]u8) *Header {
        // On recule de sizeof(Header) octets.
        const header_bytes_ptr = ptr - @sizeOf(Header);

        // // On convertit vers un pointeur sur Header avec alignement correct
        return @ptrCast(@alignCast(header_bytes_ptr));
    }

    /// Marque un bloc de mémoire précédemment alloué comme étant libre.
    fn free(
        ctx: *anyopaque,
        buf: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        // les paramètres `ctx`, `alignment` et `return_address`
        // peuvent être ignorés dans ce contexte
        _ = ctx;
        _ = alignment;
        _ = return_address;


        // Si c'est vide il n'a pas une header
        if (buf.len == 0)
            return;

        // Poiteur vers les données
        const data_ptr: [*]u8 = buf.ptr;

        // Lire le Header associé
        const header = AllocateurEtiquette.getHeader(data_ptr);
       
       // Marque le bloc comme libéré
        header.free = true;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "allocations simples" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u8);
    const c = try allocator.create(u8);
    const d = try allocator.create(u8);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 1 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(d)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(d)).len);

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(c);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);
}

test "allocations à plusieurs octets" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u64);
    const c = try allocator.create(u8);
    const d = try allocator.create(u16);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 8 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(d)).free);
    try expectEqual(2, AllocateurEtiquette.getHeader(@ptrCast(d)).len);

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(b);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(b)).len);
}

test "allocation de tableaux" {
    var buffer: [128]u8 = undefined;
    var etiquette = AllocateurEtiquette.init(&buffer);
    const allocator = etiquette.allocator();

    const a = try allocator.alloc(u8, 1);
    const b = try allocator.alloc(u32, 10);
    const c = try allocator.create(u64);

    try expect(@intFromPtr(&a[0]) + 1 <= @intFromPtr(&b[0]));
    try expectEqual(10, b.len);
    try expect(@intFromPtr(&b[9]) + 4 <= @intFromPtr(c));

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(a)).free);
    try expectEqual(1, AllocateurEtiquette.getHeader(@ptrCast(a)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(40, AllocateurEtiquette.getHeader(@ptrCast(b)).len);

    try expectEqual(false, AllocateurEtiquette.getHeader(@ptrCast(c)).free);
    try expectEqual(8, AllocateurEtiquette.getHeader(@ptrCast(c)).len);

    allocator.free(b);

    try expectEqual(true, AllocateurEtiquette.getHeader(@ptrCast(b)).free);
    try expectEqual(40, AllocateurEtiquette.getHeader(@ptrCast(b)).len);
}
