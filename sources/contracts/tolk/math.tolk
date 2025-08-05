struct SortedAddresses {
    lower: address
    higher: address
}

struct SortedAddressesAndAmounts {
    lower: address
    higher: address
    lowerAmount: coins
    higherAmount: coins
}

@inline
fun sortAddresses(a: address, b: address): SortedAddresses {
    val (_, aHash) = a.getWorkchainAndHash();
    val (_, bHash) = b.getWorkchainAndHash();

    if (aHash < bHash) {
        return { lower: a, higher: b };
    }
    return { lower: b, higher: a };
}

fun sortAddressesAndAmounts(a: address, b: address, aAmount: coins, bAmount: coins): SortedAddressesAndAmounts {
    val (_, aHash) = a.getWorkchainAndHash();
    val (_, bHash) = b.getWorkchainAndHash();

    if (aHash < bHash) {
        return {
            lower: a,
            higher: b,
            lowerAmount: aAmount,
            higherAmount: bAmount,
        };
    }
    return {
        lower: b,
        higher: a,
        lowerAmount: bAmount,
        higherAmount: aAmount,
    };
}

@pure
fun log2(num: int): int
    asm "DUP 5 THROWIFNOT UBITSIZE DEC"

@pure
fun divc(x: int, y: int): int
    asm "DIVC"

@inline
@pure
fun sqrt(num: int): int {
    if (num == 0) {
        return 0;
    }

    val s = log2(num);

    var x = (s == 1 ? (num - 1) / 2 + 1 : 1 << ((s + 1) / 2));
    var q = 0;

    do {
        q = (divc(num, x) - x) / 2;
        x += q;
    } while (q != 0);

    return x;
}
