import Foundation

/// Hand-drawn dog art. Dogs need more silhouettes than cats to stay
/// recognizable at notch size, so each ear/snout family has its own head;
/// most share the sitting body and face. See docs/study/pets.md for the
/// symbol legend. Outer outlines are added automatically.
enum DogArt {
    /// Labrador and Beagle: soft ears hanging beside a rounded skull. The
    /// blank pixel between ear and cheek becomes an outline, separating them.
    static let headFloppy = SpriteGrid(art: """
        ......BBBBBBBB......
        ....BBBBBBBBBBBB....
        ...BBBBBBffBBBBBB...
        .eeeSBBBBffBBBBSeee.
        eeeeSBBBffffBBBSeeee
        eeeeSBBBffffBBBSeeee
        eeeeSBBBffffBBBSeeee
        eeeeSBBmmmmmmBBSeeee
        eeeeSBmmmmmmmmBSeeee
        .eeeBBmmmmmmmmBBeee.
        .eee.BBmmmmmmBB.eee.
        ..e..SBBBBBBBBS..e..
        ......SSSSSSSS......
        """)

    /// Golden Retriever: long feathered ears framing a narrower face.
    static let headFluffy = SpriteGrid(art: """
        ......BBBBBBBB......
        ....BBBBBBBBBBBB....
        ..eeBBBBBBBBBBBBee..
        .eeeeSBBBBBBBBSeeee.
        eeeeeSBBBBBBBBSeeeee
        eeeeeSBBBBBBBBSeeeee
        eeeeeSBBBBBBBBSeeeee
        eeeeeSBmmmmmmBSeeeee
        eeeeeSmmmmmmmmSeeeee
        eeeee.mmmmmmmm.eeeee
        .eeee.BmmmmmmB.eeee.
        .eSee.SBBBBBBS.eeSe.
        ..e.e..SSSSSS..e.e..
        """)

    /// French Bulldog: big rounded bat ears on a broad, flat face. Zone `b`
    /// is the cheek patch of a pied coat; it stays clear of the eye so the
    /// eye never disappears into a dark patch.
    static let headBatEared = SpriteGrid(art: """
        .ee..............ee.
        eeee............eeee
        ePPe............ePPe
        ePPee..........eePPe
        ePPPe..........ePPPe
        ePPPeeBBBBBBBBeePPPe
        .eePPBBBBBBBBBBPPee.
        ..eeBBBBBBBBBBBBee..
        .bbbbBBBBBBBBBBBBBB.
        bbbbbBBBBBBBBBBBBBBB
        bbbbbBBBBBBBBBBBBBBB
        BbbbBBBmmmmmmBBBBBBB
        BBBBBBmmmmmmmmBBBBBB
        .BBBBBmmmmmmmmBBBBB.
        ..SBBBBmmmmmmBBBBS..
        ....SSSSSSSSSSSS....
        """)

    /// Corgi: tall pointed ears and a fox-like face with a center blaze.
    static let headPointyEared = SpriteGrid(art: """
        ..e..............e..
        ..ee............ee..
        .eee............eee.
        .ePee..........eePe.
        .ePPe..........ePPe.
        .ePPee........eePPe.
        .ePPPeBBBBBBBBePPPe.
        ..ePPBBBBffBBBBPPe..
        ..eBBBBBBffBBBBBBe..
        .BBBBBBBffffBBBBBBB.
        BBBBBBBffffffBBBBBBB
        BBBBBBmmmmmmmmBBBBBB
        .BBBBmmmmmmmmmmBBBB.
        ..SBBBmmmmmmmmBBBS..
        ....SSBmmmmmmBSS....
        .......SSSSSS.......
        """)

    /// Dachshund: long ears and a long snout. Zone `a` marks the brow dots
    /// of a black-and-tan coat.
    static let headLong = SpriteGrid(art: """
        ......BBBBBBBB......
        ....BBBBBBBBBBBB....
        ...BBBBBBBBBBBBBB...
        ..eeSBaaBBBBaaBSee..
        .eeeSBBBBBBBBBBSeee.
        .eeeSBBBBBBBBBBSeee.
        .eeeSBBBBBBBBBBSeee.
        .eeeSBBBmmmmBBBSeee.
        .eeee.BmmmmmmB.eeee.
        .eeee.mmmmmmmm.eeee.
        .eeee.mmmmmmmm.eeee.
        ..ee..BmmmmmmB..ee..
        ...e...SmmmmS...e...
        ........SSSS........
        """)

    /// Eyes, nose, and a panting tongue. The mouth uses the nose color
    /// rather than the outline, which turns into a light rim on dark breeds, stamped with the eyes on the head's
    /// eye row (`DogHead.eyeRow`).
    static let faceOpen = SpriteGrid(art: """
        ......LE....LE......
        ......EE....EE......
        ......EE....EE......
        .....PP.NNNN.PP.....
        .........NN.........
        ........NPPN........
        .........PP.........
        """)

    /// The same face with a longer gap to the nose, for the long snout.
    static let faceLongSnout = SpriteGrid(art: """
        ......LE....LE......
        ......EE....EE......
        ......EE....EE......
        .....PP......PP.....
        ........NNNN........
        .........NN.........
        ........NPPN........
        .........PP.........
        """)

    /// Sitting, facing the viewer. Zone `a` is the beagle's saddle.
    static let bodySit = SpriteGrid(art: """
        .....BBBBBBBBBB.....
        ....aBBccccccBBa....
        ...aaBccccccccBaa...
        ...aaBccccccccBaa...
        ...aaBBccccccBBaa...
        ..SaaSBBccccBBSaaS..
        ..BaaSBBBBBBBBSaaB..
        ..BBBSBBBBBBBBSBBB..
        ..BBBSBBBBBBBBSBBB..
        ..SBppSBBBBBBSppBS..
        ...pppp......pppp...
        """)

    /// Raised tail beside the sitting body; stubby-tailed breeds skip it.
    static let tailUp = SpriteGrid(art: """
        ..t
        .tt
        .B.
        BB.
        """)

    /// Dachshund sitting: the long body stretches out behind the head on
    /// short legs, which is what makes the breed readable from the front.
    static let bodyLong = SpriteGrid(art: """
        .....BBBBBBBBBBBBBBBB...
        ....BBBBBBBBBBBBBBBBBB.t
        ...BccccBBBBBBBBBBBBBBBt
        ...cccccBBBBBBBBBBBBBBB.
        ...cccccBBBBBBBBBBBBBBB.
        ...SccccSBBBBBBBBBBBBBS.
        ....SSSSSSSSSSSSSSSSSS..
        ....pp.pp.......pp.pp...
        ....pp.pp.......pp.pp...
        ...ppp.ppp.....ppp.ppp..
        """)

    /// Poodle: a round curly topknot over a teddy face, with long curly ears
    /// that end in round poms. Shade dots (`S`) and highlights (`A`) are the
    /// curls; the smooth muzzle stays plain so the face reads at notch size.
    static let headPoodle = SpriteGrid(art: """
        ......AA.AA.AA......
        .....BAABAABAAB.....
        ....BBBBBBBBBBBB....
        ...BBSBBSBBSBBSBB...
        ..eeSBSSBSSBSSBSee..
        .eee.BBBBBBBBBB.eee.
        eAee.BBBBBBBBBB.eeAe
        eeSe.BBBBBBBBBB.eSee
        eeee.BBBBBBBBBB.eeee
        eAee.BBBBBBBBBB.eeAe
        eeSe.BBBBBBBBBB.eSee
        eeee.BBmmmmmmBB.eeee
        eAee.BmmmmmmmmB.eeAe
        eeSe..mmmmmmmm..eSee
        .eee..SmmmmmmS..eee.
        ..e....SSSSSS....e..
        """)

    /// Poodle sitting: a curly coat with a fluffy chest and pom bracelets
    /// at the paws.
    static let bodyPoodle = SpriteGrid(art: """
        .....BBBBBBBBBB.....
        ....BBAccccccABB....
        ...BABccccccccBAB...
        ...BSBccccccccBSB...
        ..BBBABccccccBABBB..
        ..ABSSBBccccBBSSBA..
        ..BBASBBBBBBBBSABB..
        ..BSBSBABBBBABSBSB..
        ..ABBSBBSBBSBBSBBA..
        ..SBppSBBBBBBSppBS..
        ..ApppA......ApppA..
        """)

    /// The poodle's tail: a short stem curving up from the rump to a round
    /// pom that stands clear of the haunch.
    static let tailPom = SpriteGrid(art: """
        ..tt.
        .tAtt
        .tttt
        ..tt.
        .B...
        B....
        """)

    /// Shih Tzu: a gold topknot tied with a dark band above a white blaze, a
    /// gold mask around big round eyes, a flat face, and a long white beard
    /// framed by ears that hang past the chin, set apart by an outline. The
    /// band is outline, not nose, so a cap that hides it leaves the face intact.
    static let headShihTzu = SpriteGrid(art: """
        ........AAAA........
        .......AAAAAA.......
        ........SOOS........
        .....BBBBBBBBBB.....
        ...BBBBBBBBBBBBBB...
        ..eBBffBBBBBBffBBe..
        .ee.ffffBBBBffff.ee.
        eee.ffffBBBBffff.eee
        eee.ffffBBBBffff.eee
        eee.ffffBmmBffff.eee
        eee.SfffmmmmfffS.eee
        eee.SmmmmmmmmmmS.eee
        eee.mmmmmmmmmmmm.eee
        eee.mmmmmmmmmmmm.eee
        .ee..mmmmmmmmmm..ee.
        .ee...mmmmmmmm...ee.
        ..e....mm..mm....e..
        """)

    /// The Shih Tzu's flat face: big round eyes and a button nose right
    /// between them, with the tip of a tongue under it.
    static let faceShihTzu = SpriteGrid(art: """
        .....LEE....LEE.....
        .....EEE....EEE.....
        .....EEE.NN.EEE.....
        ....PP..NNNN..PP....
        ....................
        .........PP.........
        """)

    /// Shih Tzu sitting: a long flowing coat that falls to the floor in
    /// strands, with only the tips of the paws peeking out.
    static let bodyShihTzu = SpriteGrid(art: """
        .....BBBBBBBBBB.....
        ....BBBccccccBBB....
        ...BBBccccccccBBB...
        ...BBBccccccccBBB...
        ..BBSBBccccccBBSBB..
        ..BBSBBBccccBBBSBB..
        ..BSBBBBBBBBBBBBSB..
        .BBSBBSBBBBBBSBBSBB.
        .BSBBSBBBBBBBBSBBSB.
        BSBBSBBpp..ppBBSBBSB
        SB.SB.Sppp..pppS.BS.
        """)

    /// The Shih Tzu's plumed tail, curled up over the back.
    static let tailPlume = SpriteGrid(art: """
        .ttt.
        tttAt
        tAt.t
        .B...
        B....
        """)
}
