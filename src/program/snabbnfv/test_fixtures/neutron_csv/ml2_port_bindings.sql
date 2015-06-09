-- MySQL dump 10.13  Distrib 5.5.40, for debian-linux-gnu (x86_64)
--
-- Host: nbn-l8-dev2-os-8    Database: neutron_ml2
-- ------------------------------------------------------
-- Server version	5.5.40-0ubuntu0.14.04.1-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `ml2_port_bindings`
--

DROP TABLE IF EXISTS `ml2_port_bindings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `ml2_port_bindings` (
  `port_id` varchar(36) NOT NULL,
  `host` varchar(255) NOT NULL,
  `vif_type` varchar(64) NOT NULL,
  `driver` varchar(64) DEFAULT NULL,
  `segment` varchar(36) DEFAULT NULL,
  `vnic_type` varchar(64) NOT NULL DEFAULT 'normal',
  `vif_details` varchar(4095) NOT NULL DEFAULT '',
  `profile` varchar(4095) NOT NULL DEFAULT '',
  PRIMARY KEY (`port_id`),
  KEY `segment` (`segment`),
  CONSTRAINT `ml2_port_bindings_ibfk_1` FOREIGN KEY (`port_id`) REFERENCES `ports` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ml2_port_bindings_ibfk_2` FOREIGN KEY (`segment`) REFERENCES `ml2_network_segments` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
/*!40101 SET character_set_client = @saved_cs_client */;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed
