const std = @import("std");

const Header = struct {
    len: usize,
    free: bool,
};

const header_alignment = std.mem.Alignment.of(Header);

const AllocateurRecycle = struct {
    buffer: []u8,
    next: usize,

    /// Crée un allocateur à recyclage gérant la zone de mémoire délimitée
    /// par la tranche `buffer`.
    fn init(buffer: []u8) AllocateurRecycle {
        return .{
            .buffer = buffer,
            .next = 0,
        };
    }

    /// Retourne l’interface générique d’allocateur correspondant à
    /// cet allocateur à recyclage.
    fn allocator(self: *AllocateurRecycle) std.mem.Allocator {
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
        const self: *AllocateurRecycle = @ptrCast(@alignCast(ctx));

        // par la suite, `self.buffer` et `self.next` désignent les deux
        // champs de l’allocateur

        //  trouver on bloc recyclable:

        // valeur de l'alignement
        const int_alignment = @as(usize, 1) << @intFromEnum(alignment);
        const int_header_alignment = @as(usize, 1) << @intFromEnum(header_alignment);

        // pointeur que pointe au début du buffer
        var marqueur = self.buffer.ptr;

        // traverse le buffer en cherchant un bloc récyclable
        while (@intFromPtr(marqueur) < @intFromPtr(self.buffer.ptr) + self.next) {
            
            const int_marqueur = @intFromPtr(marqueur);

            // aligne le marquer avant de lire le header
            if (int_marqueur % int_header_alignment != 0) {
                // le restant qui manque pour arriver au prochain addresse aligné
                const deplacement  = int_header_alignment - (int_marqueur % int_header_alignment);
                marqueur += deplacement;

                // verifie si on est encore dans le buffer utilisé
                if (@intFromPtr(marqueur) >= @intFromPtr(self.buffer.ptr) + self.next){
                    break;
                }
            }

            // lit le header du bloc
            const header_ptr: *Header = @ptrCast(@alignCast(marqueur));
            const header = header_ptr.*;

           // pour faire une allocation de recyclage on vérifie si
            // la taille du bloc à etre recyclé est plus grande que ce qu'on veut allouer
            // et si le bloc é libre (free == true)
            if ((header.len >= len) and (header.free == true) ){
                const debut_donnees = marqueur + @sizeOf(Header);
                // vérifie si données sont bien alignés
                if (@intFromPtr(debut_donnees) % int_alignment == 0) {
                    // on met à jour la disponibilité du bloc d'espace dans le buffer
                    header_ptr.*.free = false;
                    // retourne l'address de début du nouveau bloc alloué (après le header)
                    return debut_donnees;
                }
            }

            // passe au prochain bloc
            marqueur = marqueur + @sizeOf(Header) + header.len;
        } 

        // si on ne trouve pas de bloc réutilisable, on va allouer à la fin du buffer:

        // fait l'alignement nécessaire
        const reste_header = self.next % int_header_alignment;
        if (reste_header != 0) {
            self.next += int_header_alignment - reste_header; // met à jour le next aligné
        }

        // position header
        const position_header = self.buffer.ptr + self.next;
        // calcule position des données (après header)
        const position_donnees_sans_pad = position_header + @sizeOf(Header);
        const int_position_donnees_sans_pad = @intFromPtr(position_donnees_sans_pad);

        // ajoute du padding pour aligner les données si cest necessaire
        var padding: usize = 0;
        const reste_donnees = int_position_donnees_sans_pad % int_alignment;
        if (reste_donnees != 0){
            padding = int_alignment - reste_donnees;
        }

        // vérifie s'il y a encore de l'espace dans le buffer pour une nouvelle allocation à la fin
        const espace_necessaire = @sizeOf(Header) + padding + len;
        if (self.next + espace_necessaire > self.buffer.len){
            return null;
        }

        // crée un nouveau header:
        const header_ptr: *Header = @ptrCast(@alignCast(position_header));
        header_ptr.* = .{
            .len = padding + len,
            .free = false,
        };

        // pointe au données alloués
        const donnees_ptr = position_donnees_sans_pad + padding;
        self.next += espace_necessaire; // mise à jour du self.next

        return donnees_ptr;  
    }

    /// Récupère l’en-tête associé à l’allocation débutant à l’adresse `ptr`.
    fn getHeader(ptr: [*]u8) *Header {
        // On recule de sizeof(Header) octets.
        const header_bytes_ptr = ptr - @sizeOf(Header);

        // On convertit vers un pointeur sur Header avec alignement correct
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
        const header = AllocateurRecycle.getHeader(data_ptr);
       
       // Marque le bloc comme libéré
        header.free = true;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "allocations simples" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u8);
    const c = try allocator.create(u8);
    const d = try allocator.create(u8);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 1 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(c);

    const e = try allocator.create(u8);
    try expectEqual(c, e);

    const f = try allocator.create(u8);
    try expect(@intFromPtr(d) + 1 <= @intFromPtr(f));
}

test "allocations à plusieurs octets" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.create(u8);
    const b = try allocator.create(u64);
    const c = try allocator.create(u8);
    const d = try allocator.create(u16);

    try expect(@intFromPtr(a) + 1 <= @intFromPtr(b));
    try expect(@intFromPtr(b) + 8 <= @intFromPtr(c));
    try expect(@intFromPtr(c) + 1 <= @intFromPtr(d));

    a.* = 4;
    b.* = 5;
    c.* = 6;
    d.* = 7;

    try expectEqual(4, a.*);
    try expectEqual(5, b.*);
    try expectEqual(6, c.*);
    try expectEqual(7, d.*);

    allocator.destroy(a);
    allocator.destroy(b);
    allocator.destroy(c);
    allocator.destroy(d);

    const e = try allocator.create(u24);
    try expectEqual(@intFromPtr(b), @intFromPtr(e));

    const f = try allocator.create(u16);
    try expectEqual(@intFromPtr(d), @intFromPtr(f));

    const g = try allocator.create(u16);
    try expect(@intFromPtr(d) + 2 <= @intFromPtr(g));
}

test "allocation de tableaux" {
    var buffer: [128]u8 = undefined;
    var recycle = AllocateurRecycle.init(&buffer);
    const allocator = recycle.allocator();

    const a = try allocator.alloc(u8, 1);
    const b = try allocator.alloc(u32, 10);
    const c = try allocator.create(u64);

    try expect(@intFromPtr(&a[0]) + 1 <= @intFromPtr(&b[0]));
    try expectEqual(10, b.len);
    try expect(@intFromPtr(&b[9]) + 4 <= @intFromPtr(c));

    allocator.free(b);

    const d = try allocator.alloc(u64, 4);
    try expectEqual(@intFromPtr(b.ptr), @intFromPtr(d.ptr));
}
