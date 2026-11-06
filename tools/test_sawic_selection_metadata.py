"""Refuse aggregate claims that transfer a replacement pass to another image."""
import unittest

from check_repaired_sawic import check_home_selection_metadata


class SelectionMetadataControls(unittest.TestCase):
    def setUp(self):
        self.selected='a'*64
        self.captured='b'*64
        self.timing={'bitstream_sha256':self.selected,'reported_core_fmax_mhz':25.002}
        self.result={'fpga_image_sha256':self.captured,'result':'PASS'}
        self.root={'demonstrations':{'simplestories-v2-5m':{'home_authorization':{
            'selected_image_sha256':self.selected,'reported_core_fmax_mhz':25.002,
            'physical_model_replacement_campaign_passed':True,
            'physical_model_replacement_campaign_image_sha256':self.captured,
            'physical_model_replacement_selected_image_passed':False}}}}
        self.model={'variants':{'home-authorization':{
            'selected_image_sha256':self.selected,'reported_core_fmax_mhz':25.002,
            'physical_model_replacement_selected_image_passed':False,
            'physical_model_replacement':{'image_sha256':self.captured,
                'passed':True,'applies_to_selected_image':False}}}}

    def check(self):
        return check_home_selection_metadata(self.root,self.model,self.timing,self.result)

    def test_historical_pass_keeps_its_own_image(self):
        row=self.check()
        self.assertTrue(row['recorded_pass'])
        self.assertFalse(row['selected_image_pass'])

    def test_root_cannot_transfer_the_pass(self):
        self.root['demonstrations']['simplestories-v2-5m']['home_authorization']['physical_model_replacement_selected_image_passed']=True
        with self.assertRaises(AssertionError):self.check()

    def test_model_cannot_transfer_the_pass(self):
        self.model['variants']['home-authorization']['physical_model_replacement']['applies_to_selected_image']=True
        with self.assertRaises(AssertionError):self.check()

    def test_wrong_selected_fmax_is_rejected(self):
        self.root['demonstrations']['simplestories-v2-5m']['home_authorization']['reported_core_fmax_mhz']=25.005
        with self.assertRaises(AssertionError):self.check()

    def test_unscoped_aggregate_is_rejected(self):
        del self.root['demonstrations']['simplestories-v2-5m']['home_authorization']['physical_model_replacement_campaign_image_sha256']
        with self.assertRaises(KeyError):self.check()

    def test_a_matching_completed_image_can_be_recorded(self):
        self.result['fpga_image_sha256']=self.selected
        home=self.root['demonstrations']['simplestories-v2-5m']['home_authorization']
        home['physical_model_replacement_campaign_image_sha256']=self.selected
        home['physical_model_replacement_selected_image_passed']=True
        model=self.model['variants']['home-authorization']
        model['physical_model_replacement']['image_sha256']=self.selected
        model['physical_model_replacement']['applies_to_selected_image']=True
        model['physical_model_replacement_selected_image_passed']=True
        self.assertTrue(self.check()['selected_image_pass'])


if __name__=='__main__':unittest.main()
