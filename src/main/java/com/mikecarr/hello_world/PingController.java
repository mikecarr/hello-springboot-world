package com.mikecarr.hello_world;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseBody;

@Controller
@RequestMapping("/")
public class PingController {


    @RequestMapping("/ping")
    @ResponseBody
    public String ping() {
        // Create a YAML string
        String yaml = "ping: pong";
        return yaml;
    }
}
