struct SortedAddresses {
    lower: address
    higher: address
}

struct SortedAddressesAndAmounts {
    lower: address
    higher: address
    higherAmount: coins
    lowerAmount: coins
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
