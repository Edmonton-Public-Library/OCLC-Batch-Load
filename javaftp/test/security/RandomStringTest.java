/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package security;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 *
 * @author andrew
 */
public class RandomStringTest
{
    
    public RandomStringTest()
    {
    }

    /**
     * Test of nextString method, of class RandomString.
     */
    @Test
    public void testNextString()
    {
        System.out.println("==nextString==");
        RandomString instance = new RandomString(8);
        
        String result = instance.nextString();
        System.out.println("RAN:"+result);
    }
    
}
