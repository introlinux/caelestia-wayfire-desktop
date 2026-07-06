import QtQuick
import Caelestia.Config

NumberAnimation {
    enum Type {
        StandardSmall = 0,
        Standard,
        StandardLarge,
        StandardExtraLarge,
        EmphasizedSmall,
        Emphasized,
        EmphasizedLarge,
        EmphasizedExtraLarge,
        FastSpatial,
        DefaultSpatial,
        SlowSpatial
    }

    property int type: Anim.Standard

    duration: {
        if (type < Anim.StandardSmall || type > Anim.SlowSpatial)
            return Tokens.anim.durations.normal;

        if (type == Anim.FastSpatial)
            return Tokens.anim.durations.expressiveFastSpatial;
        if (type == Anim.DefaultSpatial)
            return Tokens.anim.durations.expressiveDefaultSpatial;
        if (type == Anim.SlowSpatial)
            return Tokens.anim.durations.expressiveSlowSpatial;

        const idx = type % 4;
        if (idx === 0) return Tokens.anim.durations.small;
        if (idx === 1) return Tokens.anim.durations.normal;
        if (idx === 2) return Tokens.anim.durations.large;
        if (idx === 3) return Tokens.anim.durations.extraLarge;
        return Tokens.anim.durations.normal;
    }
    easing: {
        if (type == Anim.FastSpatial)
            return Tokens.anim.expressiveFastSpatial;
        if (type == Anim.DefaultSpatial)
            return Tokens.anim.expressiveDefaultSpatial;
        if (type == Anim.SlowSpatial)
            return Tokens.anim.expressiveSlowSpatial;

        if (type >= Anim.EmphasizedSmall && type <= Anim.EmphasizedExtraLarge)
            return Tokens.anim.emphasized;
        return Tokens.anim.standard;
    }
}
