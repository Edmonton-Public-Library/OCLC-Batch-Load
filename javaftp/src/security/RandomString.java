/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package security;

import java.util.Random;

public class RandomString
{
    private final char[] symbols = new char[36];
    private final Random random = new Random();
    private final char[] buf;

    public RandomString(int length)
    {
        for (int idx = 0; idx < 10; ++idx)
        {
            symbols[idx] = (char) ('0' + idx);
        }
        for (int idx = 10; idx < 36; ++idx)
        {
            symbols[idx] = (char) ('a' + idx - 10);
        }
        if (length < 1)
        {
            throw new IllegalArgumentException("length < 1: " + length);
        }
        buf = new char[length];
    }

    public String nextString()
    {
        for (int idx = 0; idx < buf.length; ++idx) 
        {
            buf[idx] = symbols[random.nextInt(symbols.length)];
        }
        return new String(buf);
    }
}
