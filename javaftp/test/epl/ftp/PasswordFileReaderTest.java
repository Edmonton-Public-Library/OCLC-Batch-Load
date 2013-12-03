/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package epl.ftp;

import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.junit.Test;
import static org.junit.Assert.*;

/**
 *
 * @author andrew
 */
public class PasswordFileReaderTest
{
    
    public PasswordFileReaderTest()
    {
    }

    /**
     * Test of generateNewPassword method, of class PasswordFileReader.
     */
    @Test
    public void testGenerateNewPassword()
    {
        System.out.println("==generateNewPassword==");
        PasswordFileReader instance = null;
        try
        {
            instance = new OCLCPasswordFile();
        }
        catch (IOException ex)
        {
            Logger.getLogger(PasswordFileReaderTest.class.getName()).log(Level.SEVERE, null, ex);
        }
        
        String expResult = instance.getPassword();
        instance.resave(expResult);
        
        String result = instance.generateNewPassword();
        System.out.println("PASSWORD:" + result);
        instance.resave(result);
    }
    
}
