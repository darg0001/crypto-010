module AES where

import Numeric
import Data.Char
import Data.Bits
import Data.Word
import Data.List
import Data.Ord

-- | Common methods

-- break the list into blocks of n items
split _ [] = []
split n xs = a : split n b where
    (a, b) = splitAt n xs

-- hex string -> [Char]
decode :: String -> [Word8]
decode xs = map (fromIntegral . fst . head . readHex) $ split 2 xs
-- [Char] -> hex string
encode :: [Word8] -> String
encode = concatMap hex

decodeStr xs = map (chr . fst . head . readHex) $ split 2 xs
encodeStr xs = concatMap hexStr $ map ord xs
hexStr x = pad $ showHex x "" where
    pad c | length c == 1 = "0" ++ c
    pad c = c

bin x = showIntAtBase 2 intToDigit x ""

hex :: Word8 -> String
hex x = pad $ showHex x "" where
    pad c | length c == 1 = "0" ++ c
    pad c = c

-- prints only ascii chars, replaces the rest with space
human :: [Char] -> [Char]
human = map flt where
    flt c | valid c = c
    flt _ = '.'
    valid c = isPrint c || c == ' '

display (i, x) = putStrLn $ hex i ++ " " ++ x

-- | Specific

cbcKey1 = "140b41b22a29beb4061bda66b6747e14"
cbcCt1 = "4ca00ff4c898d61e1edbf1800618fb2828a226d160dad07883d04e008a7897ee2e4b7465d5290d0c0e6c6822236e1daafb94ffe0c5da05d9476be028ad7c1d81"

keyZeroes = decode "00000000000000000000000000000000"
keyFF = decode "ffffffffffffffffffffffffffffffff"

--testKey = encode keyZeroes
--testMessage = encodeStr "HelloWorld123456"
testKey = encodeStr "mysecretpassword"
testMessage = encodeStr "Secret Message A"
testExpected = "e8da47acc08bc751745ef8fbff44e107"
test = aesHighlevel testKey testMessage
untest = unaesHighlevel testKey (AES.encode $ test)

nistKey = "2b7e151628aed2a6abf7158809cf4f3c"
nistMessage = "6bc1bee22e409f96e93d7e117393172a"
nistExpected = "3ad77bb40d7a3660a89ecaf32466ef97"
nist = aesHighlevel nistKey nistMessage
-- expected CT: e8da47acc08bc751745ef8fbff44e107

fipsKey = "000102030405060708090a0b0c0d0e0f"
fipsMessage = "00112233445566778899aabbccddeeff"
fipsExpected = "69c4e0d86a7b0430d8cdb78070b4c55a"
fips = aesHighlevel fipsKey fipsMessage
unfips = unaesHighlevel fipsKey (AES.encode $ fips)

mixColumnsMatrix :: [[Word8]]
mixColumnsMatrix = [[2, 3, 1, 1],
                    [1, 2, 3, 1],
                    [1, 1, 2, 3],
                    [3, 1, 1, 2]]

invMixColumnsMatrix :: [[Word8]]
invMixColumnsMatrix = [[14, 11, 13, 9],
                       [9, 14, 11, 13],
                       [13, 9, 14, 11],
                       [11, 13, 9, 14]]

-- State Key => NewState
type Modifier = [Word8] -> [Word8] -> [Word8]

aes :: [Modifier] -> [Modifier] -> [Modifier] -> ([Word8] -> [[Word8]]) -> [Word8] -> [Word8] -> [Word8]
aes initial intermediate final expand key state =
    let keys = expand key
        modifiers = [initial] ++ replicate 9 intermediate ++ [final]
    in foldl execRound state $ zip keys modifiers

execRound state (key, modifiers) = foldl (\state m -> m state key) state modifiers

aesEncrypt :: [Word8] -> [Word8] -> [Word8]
aesEncrypt = aes initial intermediate final expand where
    expand key   = split 16 $ keyExpansion key
    initial      = [modAddRoundKey]
    intermediate = [modSubBytes, modShiftRows, modMixColumns, modAddRoundKey]
    final        = [modSubBytes, modShiftRows, modAddRoundKey]

aesDecrypt :: [Word8] -> [Word8] -> [Word8]
aesDecrypt = aes initial intermediate final expand where
    expand key   = reverse $ split 16 $ keyExpansion key
    -- According to http://csrc.nist.gov/publications/fips/fips197/fips-197.pdf
    initial      = [modAddRoundKey]
    intermediate = [modInvShiftRows, modInvSubBytes, modAddRoundKey, modInvMixColumns]
    final        = [modInvShiftRows, modInvSubBytes, modAddRoundKey]

-- State -> Key -> NewState
modAddRoundKey   = xorwords
modSubBytes      = subBytes (sBox sBoxTable)
modInvSubBytes   = subBytes (sBox invSBoxTable)
modShiftRows     = shiftRows rotateLeft
modInvShiftRows  = shiftRows rotateRight
modMixColumns    = mixColumns mixColumnsMatrix
modInvMixColumns = mixColumns invMixColumnsMatrix

subBytes  sbox    state _ = map sbox state
shiftRows rotate' state _ = outro where
    intro  = transpose $ split 4 state
    middle = zipWith rotate' [0..3] intro
    outro  = concat $ transpose $ middle
mixColumns matrix state _ = concat result where
    result = zipWith mulColumn (repeat matrix) state'
    state' = split 4 state

    -- Helpers
    mulVec a b = foldl1 (xor . fromIntegral) $ zipWith gMul a b
    mulColumn matrix vec = zipWith mulVec matrix (repeat vec)

aesHighlevel :: String -> String -> [Word8]
aesHighlevel hexKey hexMessage = aesEncrypt (decode hexKey) (decode hexMessage)

unaesHighlevel :: String -> String -> [Word8]
unaesHighlevel hexKey hexMessage = aesDecrypt (decode hexKey) (decode hexMessage)

--aes = aesHighlevel cbcKey1 cbcCt1
aesFull = aesHighlevel testKey testMessage

-- | Nice AES manual
-- http://www.samiam.org/rijndael.html

nfirst            = take
nlast       n  xs = drop (length xs - n) xs
nrotate     n  xs = take (length xs) $ drop (n `mod` length xs) $ cycle xs
rotateLeft        = nrotate
rotateRight n     = nrotate (negate n)
xorwords          = zipWith xor

rConTable :: [Word8]
rConTable = [0x8d, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36]

sBoxTable :: [Word8]
sBoxTable = [0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
             0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
             0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
             0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
             0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
             0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
             0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
             0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
             0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
             0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
             0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
             0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
             0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
             0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
             0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
             0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16]

invSBoxTable :: [Word8]
invSBoxTable = [0x52, 0x09, 0x6A, 0xD5, 0x30, 0x36, 0xA5, 0x38, 0xBF, 0x40, 0xA3, 0x9E, 0x81, 0xF3, 0xD7, 0xFB,
                0x7C, 0xE3, 0x39, 0x82, 0x9B, 0x2F, 0xFF, 0x87, 0x34, 0x8E, 0x43, 0x44, 0xC4, 0xDE, 0xE9, 0xCB,
                0x54, 0x7B, 0x94, 0x32, 0xA6, 0xC2, 0x23, 0x3D, 0xEE, 0x4C, 0x95, 0x0B, 0x42, 0xFA, 0xC3, 0x4E,
                0x08, 0x2E, 0xA1, 0x66, 0x28, 0xD9, 0x24, 0xB2, 0x76, 0x5B, 0xA2, 0x49, 0x6D, 0x8B, 0xD1, 0x25,
                0x72, 0xF8, 0xF6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xD4, 0xA4, 0x5C, 0xCC, 0x5D, 0x65, 0xB6, 0x92,
                0x6C, 0x70, 0x48, 0x50, 0xFD, 0xED, 0xB9, 0xDA, 0x5E, 0x15, 0x46, 0x57, 0xA7, 0x8D, 0x9D, 0x84,
                0x90, 0xD8, 0xAB, 0x00, 0x8C, 0xBC, 0xD3, 0x0A, 0xF7, 0xE4, 0x58, 0x05, 0xB8, 0xB3, 0x45, 0x06,
                0xD0, 0x2C, 0x1E, 0x8F, 0xCA, 0x3F, 0x0F, 0x02, 0xC1, 0xAF, 0xBD, 0x03, 0x01, 0x13, 0x8A, 0x6B,
                0x3A, 0x91, 0x11, 0x41, 0x4F, 0x67, 0xDC, 0xEA, 0x97, 0xF2, 0xCF, 0xCE, 0xF0, 0xB4, 0xE6, 0x73,
                0x96, 0xAC, 0x74, 0x22, 0xE7, 0xAD, 0x35, 0x85, 0xE2, 0xF9, 0x37, 0xE8, 0x1C, 0x75, 0xDF, 0x6E,
                0x47, 0xF1, 0x1A, 0x71, 0x1D, 0x29, 0xC5, 0x89, 0x6F, 0xB7, 0x62, 0x0E, 0xAA, 0x18, 0xBE, 0x1B,
                0xFC, 0x56, 0x3E, 0x4B, 0xC6, 0xD2, 0x79, 0x20, 0x9A, 0xDB, 0xC0, 0xFE, 0x78, 0xCD, 0x5A, 0xF4,
                0x1F, 0xDD, 0xA8, 0x33, 0x88, 0x07, 0xC7, 0x31, 0xB1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xEC, 0x5F,
                0x60, 0x51, 0x7F, 0xA9, 0x19, 0xB5, 0x4A, 0x0D, 0x2D, 0xE5, 0x7A, 0x9F, 0x93, 0xC9, 0x9C, 0xEF,
                0xA0, 0xE0, 0x3B, 0x4D, 0xAE, 0x2A, 0xF5, 0xB0, 0xC8, 0xEB, 0xBB, 0x3C, 0x83, 0x53, 0x99, 0x61,
                0x17, 0x2B, 0x04, 0x7E, 0xBA, 0x77, 0xD6, 0x26, 0xE1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0C, 0x7D]

rotate8 (x:xs) = xs ++ [x]

sBox :: [Word8] -> Word8 -> Word8
sBox table x = table !! (fromIntegral x)
rCon :: [Word8] -> Word8 -> Word8
rCon table x = table !! (fromIntegral x)

gMul :: Word8 -> Word8 -> Word8
gMul a b = fromIntegral resultP where
    (resultP, _, _ ) = foldl inner (0, a, b) [0..7]

    inner :: (Integer, Word8, Word8) -> Integer -> (Integer, Word8, Word8)
    inner (p, a, b) i =
        let newP = if b .&. 0x01 == 0x01 then p `xor` (fromIntegral a) else p
            hiBit = a .&. 0x80
            newA = shift (fromIntegral a) 1
            newA2 = if hiBit == 0x80 then newA `xor` 0x1B else newA
            newB = shift (fromIntegral b) (-1)
        in (newP, newA2, newB)

-- | Key expansion
keyExpansionCore i t =
    let a = rotate8 t
        b = map (sBox sBoxTable) a
        c = rCon rConTable i
        d = head b `xor` c
    in d : tail b

keyExpansionRound key i =
    let newT = keyExpansionCore i
        oldT = id

        next getT key = key ++ four where
            four = xorwords t (nfirst 4 $ nlast 16 key)
            t = getT $ nlast 4 key

    in next oldT $ next oldT $ next oldT $ next newT key

-- | Rijndael key schedule
keyExpansion key = foldl keyExpansionRound key [1..10]
